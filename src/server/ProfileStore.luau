--!strict
-- ProfileStore is the in-house, session-locked DataStore wrapper. It replaces
-- the former third-party DataKeep dependency. It is the single owner of every
-- DataStore call in the library (the economy-core ladder forbids scattering
-- DataStore access across scripts).
--
-- Session locking
--   Each record stored under "<prefix><userId>" is shaped:
--       { data = <ProfileData>, lock = { jobId, placeId, heartbeat } | nil }
--   A lock is "live" while os.time() - heartbeat < SESSION_LOCK_EXPIRE. On
--   load we acquire the lock through UpdateAsync only if no other server holds
--   a live lock; otherwise we retry a few times then refuse the load (the
--   caller kicks the player). The auto-save loop refreshes our heartbeat, so a
--   running server keeps ownership and a crashed one's lock goes stale and can
--   be reclaimed. This is what prevents two servers editing one profile and
--   corrupting it.
--
-- Durability
--   An auto-save loop persists every active profile on an interval, and a
--   game:BindToClose handler releases (final-saves + unlocks) all profiles
--   before shutdown so no in-flight balance change is lost on a restart.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared")
local Types = require(EconomyShared:WaitForChild("Types"))
local Constants = require(EconomyShared:WaitForChild("Constants"))

type ProfileData = Types.ProfileData

-- A held session. `data` is the authoritative in-memory state; CurrencyService
-- mutates it in place and ProfileStore persists it.
export type Profile = {
	userId: number,
	key: string,
	data: ProfileData,
}

type Lock = { jobId: string, placeId: number, heartbeat: number }
type Record = { data: any, lock: Lock? }

local ProfileStore = {}

-- A stable, unique identity for this server process. game.JobId is empty in
-- Studio, so fall back to a GUID there so local testing still locks sanely.
local SERVER_ID: string = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local dataStore: DataStore? = nil
local defaultFactory: (() -> ProfileData)? = nil
local started = false

-- userId -> Profile for every session this server currently owns.
local active: { [number]: Profile } = {}

-- Deep-copies a plain table so distinct profiles never share nested tables
-- (e.g. the default wallet) by reference.
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Fills any keys missing from `target` using `template`, recursing into nested
-- tables. Lets profiles gain new fields (e.g. a newly registered currency)
-- without wiping existing data.
local function reconcile(target: any, template: any): any
	if type(target) ~= "table" then
		return deepCopy(template)
	end
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			reconcile(target[key], value)
		end
	end
	return target
end

local function buildDefault(): ProfileData
	assert(defaultFactory ~= nil, "ProfileStore.setup must be called before use")
	return defaultFactory()
end

local function isLockLive(lock: Lock?): boolean
	return lock ~= nil and (os.time() - lock.heartbeat) < Constants.SESSION_LOCK_EXPIRE
end

local function ownLock(): Lock
	return { jobId = SERVER_ID, placeId = game.PlaceId, heartbeat = os.time() }
end

-- Runs a DataStore call with exponential-backoff retries. Returns
-- (true, value) on success, or (false, nil) once retries are exhausted.
local function withRetry(label: string, fn: () -> any): (boolean, any)
	for attempt = 1, Constants.DATASTORE_MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[economy] %s failed (attempt %d/%d): %s", label, attempt, Constants.DATASTORE_MAX_RETRIES, tostring(result)))
		if attempt < Constants.DATASTORE_MAX_RETRIES then
			task.wait(Constants.DATASTORE_RETRY_BASE * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

-- Configures the store and starts the auto-save loop + BindToClose handler.
-- Safe to call once at boot; subsequent calls only refresh configuration.
function ProfileStore.setup(storeName: string, factory: () -> ProfileData)
	dataStore = DataStoreService:GetDataStore(storeName)
	defaultFactory = factory

	if started then
		return
	end
	started = true

	-- Auto-save loop: periodically persist every active profile (which also
	-- refreshes its session-lock heartbeat). Snapshot the profiles first so a
	-- concurrent release (PlayerRemoving) can't mutate the set mid-iteration.
	task.spawn(function()
		while true do
			task.wait(Constants.AUTO_SAVE_INTERVAL)
			local snapshot: { Profile } = {}
			for _, profile in active do
				table.insert(snapshot, profile)
			end
			for _, profile in snapshot do
				task.spawn(ProfileStore.save, profile)
			end
		end
	end)

	-- BindToClose: final-save and unlock every active profile before the
	-- server dies. Roblox grants up to 30s here; we wait for all releases.
	game:BindToClose(function()
		local userIds: { number } = {}
		for userId in active do
			table.insert(userIds, userId)
		end

		local remaining = #userIds
		if remaining == 0 then
			return
		end

		for _, userId in userIds do
			task.spawn(function()
				ProfileStore.release(userId)
				remaining -= 1
			end)
		end

		while remaining > 0 do
			task.wait()
		end
	end)
end

-- Loads (and session-locks) a player's profile. Returns the Profile on
-- success, or nil if another live server holds the lock after all retries.
function ProfileStore.loadAsync(userId: number): Profile?
	local store = assert(dataStore, "ProfileStore.setup must be called before loadAsync")
	local key = Constants.PROFILE_KEY_PREFIX .. userId

	for attempt = 1, Constants.LOCK_ACQUIRE_ATTEMPTS do
		local ok, record = withRetry("loadAsync(" .. key .. ")", function()
			local updated = store:UpdateAsync(key, function(old: Record?): Record
				local current: Record = old or { data = buildDefault(), lock = nil }

				-- Refuse to take a lock another live server still owns; return
				-- the record untouched so we can detect the contention below.
				if current.lock ~= nil and current.lock.jobId ~= SERVER_ID and isLockLive(current.lock) then
					return current
				end

				current.data = reconcile(current.data, buildDefault())
				current.lock = ownLock()
				return current
			end)
			return updated
		end)

		if ok and record ~= nil and record.lock ~= nil and record.lock.jobId == SERVER_ID then
			local profile: Profile = { userId = userId, key = key, data = record.data }
			active[userId] = profile
			return profile
		end

		-- Contended (or transient failure): wait and retry to let a server-hop
		-- release, or for a crashed lock to expire.
		if attempt < Constants.LOCK_ACQUIRE_ATTEMPTS then
			task.wait(Constants.LOCK_ACQUIRE_DELAY)
		end
	end

	warn(string.format("[economy] could not acquire session lock for %s", key))
	return nil
end

-- Persists a profile's current data and refreshes its lock heartbeat. Aborts
-- without writing if another live server has stolen the lock (we went stale),
-- so we never clobber a newer session. Returns whether the save committed.
function ProfileStore.save(profile: Profile): boolean
	local store = dataStore
	if store == nil then
		return false
	end

	local ok, record = withRetry("save(" .. profile.key .. ")", function()
		local updated = store:UpdateAsync(profile.key, function(old: Record?): Record?
			local current: Record = old or { data = profile.data, lock = nil }
			if current.lock ~= nil and current.lock.jobId ~= SERVER_ID and isLockLive(current.lock) then
				return nil -- lock lost to a live server; abort this save
			end
			current.data = profile.data
			current.lock = ownLock()
			return current
		end)
		return updated
	end)

	return ok and record ~= nil
end

-- Final-saves a profile, clears its session lock, and drops it from the active
-- set. Called on player leave and during BindToClose.
function ProfileStore.release(userId: number)
	local profile = active[userId]
	if profile == nil then
		return
	end
	active[userId] = nil

	local store = dataStore
	if store == nil then
		return
	end

	withRetry("release(" .. profile.key .. ")", function()
		store:UpdateAsync(profile.key, function(old: Record?): Record?
			local current: Record = old or { data = profile.data, lock = nil }
			if current.lock ~= nil and current.lock.jobId ~= SERVER_ID and isLockLive(current.lock) then
				return nil -- not ours anymore; leave it for the owner
			end
			current.data = profile.data
			current.lock = nil -- release the session lock
			return current
		end)
		return nil
	end)
end

return ProfileStore
