--!strict
-- EconomyProvider is the entire RBClauneck Economy package in a single,
-- drop-in ModuleScript. Place it anywhere reachable by both the server and
-- the client (ReplicatedStorage works out of the box) and require it; the
-- module detects which side it is running on via RunService and wires
-- itself up automatically — session-locked persistence and player lifecycle
-- on the server, replicated wallet sync and the built-in wallet UI on the
-- client. Consumers never touch wiring code: they only call functions on
-- the table this module returns.
--
-- Server is authoritative: every balance is written through addMoney /
-- minusMoney, validated, persisted through the built-in session-locked
-- DataStore wrapper, and replicated to the owning client over a single
-- RemoteEvent this module creates for itself. The client is strictly
-- read-only: it mirrors replicated state and never mutates balances.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local IS_SERVER = RunService:IsServer()

--------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------

export type CurrencyId = string

export type CurrencyDefinition = {
	id: CurrencyId,
	displayName: string,
	default: number,
	max: number,
	isBase: boolean,
}

export type CustomCurrencyOptions = {
	id: CurrencyId,
	displayName: string?,
	default: number?,
	max: number?,
}

export type Wallet = { [CurrencyId]: number }

export type MutationResult = {
	ok: boolean,
	balance: number?,
	reason: string?,
}

type ProfileData = { wallet: Wallet }

type WalletSyncPayload =
	{ kind: "full", wallet: Wallet }
	| { kind: "update", currency: CurrencyId, balance: number }

type Listener = (CurrencyId, number) -> ()

--------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------

local REMOTE_EVENT_NAME = "EconomyProviderRemote"
local DATASTORE_NAME = "EconomyProfiles_v1"
local PROFILE_KEY_PREFIX = "Player_"

-- Session locking: a profile's lock is considered stale (and stealable by
-- another server) once its heartbeat is older than this many seconds. The
-- auto-save loop refreshes the heartbeat well within the window, so a live
-- server never loses its own lock; only a crashed one does.
local SESSION_LOCK_EXPIRE = 600
local AUTO_SAVE_INTERVAL = 60
local DATASTORE_MAX_RETRIES = 4
local DATASTORE_RETRY_BASE = 1
local LOCK_ACQUIRE_ATTEMPTS = 5
local LOCK_ACQUIRE_DELAY = 2
local MIN_BALANCE = 0
-- Roblox doubles lose integer precision beyond 2^53; stay well under it.
local MAX_SAFE_AMOUNT = 2 ^ 53 - 1

--------------------------------------------------------------------------
-- Currency registry (shared by both sides)
--------------------------------------------------------------------------

local byId: { [CurrencyId]: CurrencyDefinition } = {}
local ordered: { CurrencyDefinition } = {}

local function addDefinition(definition: CurrencyDefinition)
	byId[definition.id] = definition
	table.insert(ordered, definition)
end

local BASE_CURRENCIES: { CurrencyDefinition } = {
	{ id = "coin", displayName = "Coin", default = 0, max = MAX_SAFE_AMOUNT, isBase = true },
	{ id = "copper", displayName = "Copper", default = 0, max = MAX_SAFE_AMOUNT, isBase = true },
	{ id = "silver", displayName = "Silver", default = 0, max = MAX_SAFE_AMOUNT, isBase = true },
	{ id = "gold", displayName = "Gold", default = 0, max = MAX_SAFE_AMOUNT, isBase = true },
}

for _, definition in BASE_CURRENCIES do
	addDefinition(table.freeze(definition))
end

local function buildDefaultWallet(): Wallet
	local wallet: Wallet = {}
	for _, definition in ordered do
		wallet[definition.id] = definition.default
	end
	return wallet
end

--------------------------------------------------------------------------
-- Validation (server-side mutation guards)
--------------------------------------------------------------------------

type AmountCheck = { test: (amount: any) -> boolean, reason: string }

-- Guard clauses on unrelated conditions, expressed as an ordered, data-driven
-- list instead of an if/elseif ladder. They run in order and stop at the
-- first failure, so later numeric tests never see a non-number.
local AMOUNT_CHECKS: { AmountCheck } = {
	{ test = function(a) return type(a) == "number" end, reason = "amount must be a number" },
	{ test = function(a) return a == a end, reason = "amount is NaN" },
	{ test = function(a) return a ~= math.huge and a ~= -math.huge end, reason = "amount is infinite" },
	{ test = function(a) return a >= 0 end, reason = "amount must be non-negative" },
	{ test = function(a) return math.floor(a) == a end, reason = "amount must be an integer" },
	{ test = function(a) return a <= MAX_SAFE_AMOUNT end, reason = "amount exceeds maximum safe value" },
}

local function checkAmount(amount: number): (boolean, string?)
	for _, check in AMOUNT_CHECKS do
		if not check.test(amount) then
			return false, check.reason
		end
	end
	return true, nil
end

local function checkResult(result: number, max: number): (boolean, string?)
	if result < MIN_BALANCE then
		return false, "insufficient funds"
	end
	if result > max then
		return false, "balance exceeds currency maximum"
	end
	return true, nil
end

--------------------------------------------------------------------------
-- Replicated RemoteEvent (created once by the server, awaited by clients)
--------------------------------------------------------------------------

local remote: RemoteEvent
if IS_SERVER then
	local existing = script:FindFirstChild(REMOTE_EVENT_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_EVENT_NAME
		remote.Parent = script
	end
else
	remote = script:WaitForChild(REMOTE_EVENT_NAME) :: RemoteEvent
end

--------------------------------------------------------------------------
-- Server: session-locked DataStore persistence
--------------------------------------------------------------------------
-- Each record stored under "<prefix><userId>" is shaped:
--     { data = <ProfileData>, lock = { jobId, placeId, heartbeat } | nil }
-- A lock is "live" while os.time() - heartbeat < SESSION_LOCK_EXPIRE. On load
-- the lock is acquired through UpdateAsync only if no other server holds a
-- live lock; otherwise the load is retried a few times then refused (the
-- caller kicks the player). This prevents two servers editing one profile
-- and corrupting it. An auto-save loop persists every active profile on an
-- interval, and BindToClose releases (final-saves + unlocks) all profiles
-- before shutdown so no in-flight balance change is lost on a restart.

type Lock = { jobId: string, placeId: number, heartbeat: number }
type Record = { data: any, lock: Lock? }
type Profile = { userId: number, key: string, data: ProfileData }

-- A stable, unique identity for this server process. game.JobId is empty in
-- Studio, so fall back to a GUID there so local testing still locks sanely.
local SERVER_ID: string = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local dataStore: DataStore? = if IS_SERVER then DataStoreService:GetDataStore(DATASTORE_NAME) else nil
local activeProfiles: { [number]: Profile } = {}

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

-- Fills any keys missing from `target` using `template`, recursing into
-- nested tables, so profiles gain new fields (e.g. a newly registered
-- currency) without wiping existing data.
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

local function isLockLive(lock: Lock?): boolean
	return lock ~= nil and (os.time() - lock.heartbeat) < SESSION_LOCK_EXPIRE
end

local function ownLock(): Lock
	return { jobId = SERVER_ID, placeId = game.PlaceId, heartbeat = os.time() }
end

-- Runs a DataStore call with exponential-backoff retries. Returns
-- (true, value) on success, or (false, nil) once retries are exhausted.
local function withRetry(label: string, fn: () -> any): (boolean, any)
	for attempt = 1, DATASTORE_MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[EconomyProvider] %s failed (attempt %d/%d): %s", label, attempt, DATASTORE_MAX_RETRIES, tostring(result)))
		if attempt < DATASTORE_MAX_RETRIES then
			task.wait(DATASTORE_RETRY_BASE * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

-- Loads (and session-locks) a player's profile. Returns the Profile on
-- success, or nil if another live server holds the lock after all retries.
local function loadProfileAsync(userId: number): Profile?
	local store = assert(dataStore, "EconomyProvider: DataStore only available on the server")
	local key = PROFILE_KEY_PREFIX .. userId

	for attempt = 1, LOCK_ACQUIRE_ATTEMPTS do
		local ok, record = withRetry("loadAsync(" .. key .. ")", function()
			return store:UpdateAsync(key, function(old: Record?): Record
				local current: Record = old or { data = { wallet = buildDefaultWallet() }, lock = nil }

				-- Refuse to take a lock another live server still owns; return
				-- the record untouched so we can detect the contention below.
				if current.lock ~= nil and current.lock.jobId ~= SERVER_ID and isLockLive(current.lock) then
					return current
				end

				current.data = reconcile(current.data, { wallet = buildDefaultWallet() })
				current.lock = ownLock()
				return current
			end)
		end)

		if ok and record ~= nil and record.lock ~= nil and record.lock.jobId == SERVER_ID then
			local profile: Profile = { userId = userId, key = key, data = record.data }
			activeProfiles[userId] = profile
			return profile
		end

		-- Contended (or transient failure): wait and retry to let a server-hop
		-- release, or for a crashed lock to expire.
		if attempt < LOCK_ACQUIRE_ATTEMPTS then
			task.wait(LOCK_ACQUIRE_DELAY)
		end
	end

	warn(string.format("[EconomyProvider] could not acquire session lock for %s", key))
	return nil
end

-- Persists a profile's current data and refreshes its lock heartbeat. Aborts
-- without writing if another live server has stolen the lock, so a stale
-- server never clobbers a newer session.
local function saveProfile(profile: Profile): boolean
	local store = dataStore
	if store == nil then
		return false
	end

	local ok, record = withRetry("save(" .. profile.key .. ")", function()
		return store:UpdateAsync(profile.key, function(old: Record?): Record?
			local current: Record = old or { data = profile.data, lock = nil }
			if current.lock ~= nil and current.lock.jobId ~= SERVER_ID and isLockLive(current.lock) then
				return nil -- lock lost to a live server; abort this save
			end
			current.data = profile.data
			current.lock = ownLock()
			return current
		end)
	end)

	return ok and record ~= nil
end

-- Final-saves a profile, clears its session lock, and drops it from the
-- active set. Called on player leave and during BindToClose.
local function releaseProfile(userId: number)
	local profile = activeProfiles[userId]
	if profile == nil then
		return
	end
	activeProfiles[userId] = nil

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

--------------------------------------------------------------------------
-- Server: session state and the mutation API
--------------------------------------------------------------------------

-- A loaded player session: the owning Player (for replication) and the
-- authoritative wallet, which is the same table held by the Profile so
-- the auto-save loop persists it automatically.
type Session = { player: Player, profile: Profile, wallet: Wallet }

local sessions: { [number]: Session } = {}

local function syncFull(player: Player, wallet: Wallet)
	local payload: WalletSyncPayload = { kind = "full", wallet = wallet }
	remote:FireClient(player, payload)
end

local function syncUpdate(player: Player, currency: CurrencyId, balance: number)
	local payload: WalletSyncPayload = { kind = "update", currency = currency, balance = balance }
	remote:FireClient(player, payload)
end

-- Registers a player's loaded session. Missing currencies (e.g. a custom
-- currency added since last login) are back-filled with their default so
-- wallets stay complete, then the full wallet is pushed to the client.
local function bindSession(player: Player, profile: Profile)
	local wallet: Wallet = profile.data.wallet or buildDefaultWallet()
	for _, definition in ordered do
		if wallet[definition.id] == nil then
			wallet[definition.id] = definition.default
		end
	end
	profile.data.wallet = wallet

	sessions[player.UserId] = { player = player, profile = profile, wallet = wallet }
	syncFull(player, wallet)
end

local function unbindSession(userId: number)
	sessions[userId] = nil
end

-- Internal: applies a signed delta to a balance after full validation, then
-- replicates. `sign` is +1 for add, -1 for subtract. The mutated wallet is
-- the same table held by the Profile, so it is auto-saved automatically.
local function applyDelta(userId: number, currency: CurrencyId, amount: number, sign: number): MutationResult
	if not IS_SERVER then
		return { ok = false, reason = "must be called from the server" }
	end

	local session = sessions[userId]
	if not session then
		return { ok = false, reason = "no active session for player" }
	end

	local definition = byId[currency]
	if not definition then
		return { ok = false, reason = string.format("unknown currency '%s'", tostring(currency)) }
	end

	local amountOk, amountReason = checkAmount(amount)
	if not amountOk then
		return { ok = false, reason = amountReason }
	end

	local current = session.wallet[currency] or definition.default
	local result = current + (sign * amount)

	local resultOk, resultReason = checkResult(result, definition.max)
	if not resultOk then
		return { ok = false, reason = resultReason }
	end

	session.wallet[currency] = result
	syncUpdate(session.player, currency, result)

	return { ok = true, balance = result }
end

--------------------------------------------------------------------------
-- Client: read-only wallet mirror
--------------------------------------------------------------------------

local localWallet: Wallet = {}
local localListeners: { Listener } = {}

local function notifyLocal(currency: CurrencyId, balance: number)
	for _, listener in localListeners do
		task.spawn(listener, currency, balance)
	end
end

local function applyFull(snapshot: Wallet)
	for currency, balance in snapshot do
		localWallet[currency] = balance
		notifyLocal(currency, balance)
	end
end

local function applyUpdate(currency: CurrencyId, balance: number)
	localWallet[currency] = balance
	notifyLocal(currency, balance)
end

--------------------------------------------------------------------------
-- Client: built-in wallet UI
--------------------------------------------------------------------------
-- Presentation only: reads the local wallet mirror and never mutates
-- economy state. Rows are created once and then shown/hidden and reordered
-- in place, so filtering and sorting allocate nothing per keystroke.

local ROW_HEIGHT = 36
local PANEL_SIZE = UDim2.fromOffset(360, 440)
local COLOR_BG = Color3.fromRGB(24, 26, 32)
local COLOR_PANEL = Color3.fromRGB(32, 35, 43)
local COLOR_ROW = Color3.fromRGB(40, 44, 54)
local COLOR_TEXT = Color3.fromRGB(235, 238, 245)
local COLOR_MUTED = Color3.fromRGB(150, 156, 168)
local COLOR_ACCENT = Color3.fromRGB(90, 140, 255)

local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign, text = "-", string.sub(text, 2)
	end
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	formatted = (formatted:gsub("^,", ""))
	return sign .. formatted
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

type Row = { definition: CurrencyDefinition, frame: Frame, balanceLabel: TextLabel }

local function getLocalBalance(currency: CurrencyId): number
	local value = localWallet[currency]
	if value ~= nil then
		return value
	end
	local definition = byId[currency]
	return if definition then definition.default else 0
end

-- Builds the whole panel and wires search, sort and live balance updates.
-- Returns the ScreenGui so callers can keep or destroy it.
local function mountWalletGui(): ScreenGui
	local localPlayer = Players.LocalPlayer :: Player
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EconomyWallet"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = PANEL_SIZE
	panel.BackgroundColor3 = COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	corner(panel, 12)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.BackgroundColor3 = COLOR_ACCENT
	closeButton.BackgroundTransparency = 0
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.TextColor3 = COLOR_TEXT
	closeButton.AutoButtonColor = true
	closeButton.Text = "X"
	closeButton.ZIndex = 2
	closeButton.Parent = panel
	corner(closeButton, 8)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = COLOR_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Currencies"
	title.Parent = content

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.LayoutOrder = 2
	controls.Size = UDim2.new(1, 0, 0, 32)
	controls.BackgroundTransparency = 1
	controls.Parent = content

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.Size = UDim2.new(1, -76, 1, 0)
	searchBox.Position = UDim2.fromOffset(0, 0)
	searchBox.BackgroundColor3 = COLOR_BG
	searchBox.BorderSizePixel = 0
	searchBox.Font = Enum.Font.Gotham
	searchBox.TextSize = 14
	searchBox.TextColor3 = COLOR_TEXT
	searchBox.PlaceholderText = "Search currency..."
	searchBox.PlaceholderColor3 = COLOR_MUTED
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Parent = controls
	corner(searchBox, 8)
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 10)
	searchPad.Parent = searchBox

	local sortButton = Instance.new("TextButton")
	sortButton.Name = "Sort"
	sortButton.AnchorPoint = Vector2.new(1, 0)
	sortButton.Position = UDim2.fromScale(1, 0)
	sortButton.Size = UDim2.new(0, 68, 1, 0)
	sortButton.BackgroundColor3 = COLOR_ACCENT
	sortButton.BorderSizePixel = 0
	sortButton.Font = Enum.Font.GothamMedium
	sortButton.TextSize = 14
	sortButton.TextColor3 = COLOR_TEXT
	sortButton.AutoButtonColor = true
	sortButton.Text = "A → Z"
	sortButton.Parent = controls
	corner(sortButton, 8)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "List"
	scroller.LayoutOrder = 3
	scroller.Size = UDim2.new(1, 0, 1, -80)
	scroller.BackgroundColor3 = COLOR_BG
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = COLOR_ACCENT
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = content
	corner(scroller, 8)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scroller
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.PaddingLeft = UDim.new(0, 4)
	listPad.PaddingRight = UDim.new(0, 4)
	listPad.Parent = scroller

	local rows: { Row } = {}
	local rowById: { [CurrencyId]: Row } = {}

	for _, definition in ordered do
		local frame = Instance.new("Frame")
		frame.Name = definition.id
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		frame.BackgroundColor3 = COLOR_ROW
		frame.BorderSizePixel = 0
		frame.Parent = scroller
		corner(frame, 6)

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = frame

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = COLOR_TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = definition.displayName
		nameLabel.Parent = frame

		local balanceLabel = Instance.new("TextLabel")
		balanceLabel.Size = UDim2.new(0.4, 0, 1, 0)
		balanceLabel.Position = UDim2.fromScale(0.6, 0)
		balanceLabel.BackgroundTransparency = 1
		balanceLabel.Font = Enum.Font.GothamBold
		balanceLabel.TextSize = 14
		balanceLabel.TextColor3 = COLOR_TEXT
		balanceLabel.TextXAlignment = Enum.TextXAlignment.Right
		balanceLabel.Text = formatNumber(getLocalBalance(definition.id))
		balanceLabel.Parent = frame

		local row: Row = { definition = definition, frame = frame, balanceLabel = balanceLabel }
		rows[#rows + 1] = row
		rowById[definition.id] = row
	end

	local query = ""
	local ascending = true

	local function refresh()
		local visible: { Row } = {}
		for _, row in rows do
			local def = row.definition
			local matches = query == ""
				or string.find(string.lower(def.displayName), query, 1, true) ~= nil
				or string.find(def.id, query, 1, true) ~= nil
			row.frame.Visible = matches
			if matches then
				visible[#visible + 1] = row
			end
		end

		table.sort(visible, function(a, b)
			if ascending then
				return a.definition.displayName < b.definition.displayName
			end
			return a.definition.displayName > b.definition.displayName
		end)

		for index, row in visible do
			row.frame.LayoutOrder = index
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		query = string.lower(searchBox.Text)
		refresh()
	end)

	sortButton.Activated:Connect(function()
		ascending = not ascending
		sortButton.Text = if ascending then "A → Z" else "Z → A"
		refresh()
	end)

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenWallet"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 20, 1, -20)
	openButton.Size = UDim2.fromOffset(130, 36)
	openButton.BackgroundColor3 = COLOR_PANEL
	openButton.BorderSizePixel = 0
	openButton.Font = Enum.Font.GothamMedium
	openButton.TextSize = 14
	openButton.TextColor3 = COLOR_TEXT
	openButton.AutoButtonColor = true
	openButton.Text = "Open Wallet"
	openButton.Parent = screenGui
	corner(openButton, 8)

	openButton.Activated:Connect(function()
		panel.Visible = true
	end)

	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	refresh()
	screenGui.Parent = playerGui

	table.insert(localListeners, function(currency: CurrencyId, balance: number)
		local row = rowById[currency]
		if row then
			row.balanceLabel.Text = formatNumber(balance)
		end
	end)

	return screenGui
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

local EconomyProvider = {}

-- Registers a custom currency. Must be called during boot (before profiles
-- load), on both the server and the client, so every wallet is seeded
-- consistently and the client can label it. Returns the frozen definition.
function EconomyProvider.registerCurrency(options: CustomCurrencyOptions): CurrencyDefinition
	assert(type(options) == "table", "registerCurrency expects an options table")

	local id = options.id
	assert(type(id) == "string" and #id > 0, "currency id must be a non-empty string")
	assert(id == string.lower(id), "currency id must be lowercase")
	assert(byId[id] == nil, string.format("currency '%s' is already registered", id))

	local default = options.default or 0
	local max = options.max or MAX_SAFE_AMOUNT
	assert(default >= MIN_BALANCE, "default balance cannot be negative")
	assert(max >= default, "max must be greater than or equal to default")

	local definition: CurrencyDefinition = table.freeze({
		id = id,
		displayName = options.displayName or id,
		default = default,
		max = max,
		isBase = false,
	})

	addDefinition(definition)
	return definition
end

function EconomyProvider.getCurrencyDefinition(id: CurrencyId): CurrencyDefinition?
	return byId[id]
end

-- Returns the shared, insertion-ordered list of every registered definition
-- (base currencies first, then customs in registration order). Frozen —
-- iterate, never mutate.
function EconomyProvider.getAllCurrencies(): { CurrencyDefinition }
	return ordered
end

-- Adds `amount` of `currency` to the player. Validated against overflow and
-- the currency ceiling. Server-only; safe for any trusted server caller.
function EconomyProvider.addMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return applyDelta(userId, currency, amount, 1)
end

-- Removes `amount` of `currency`. Fails (without mutating) when the player
-- lacks sufficient funds. Server-only; same params as addMoney.
function EconomyProvider.minusMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return applyDelta(userId, currency, amount, -1)
end

-- Reads a single server-authoritative balance. Server-only. Returns nil if
-- the player has no session or the currency is unknown.
function EconomyProvider.getBalance(userId: number, currency: CurrencyId): number?
	if not IS_SERVER then
		return nil
	end
	local session = sessions[userId]
	if not session then
		return nil
	end
	return session.wallet[currency]
end

-- Returns the player's whole server-authoritative wallet. Server-only.
-- Returns nil if they have no active session.
function EconomyProvider.getWallet(userId: number): Wallet?
	if not IS_SERVER then
		return nil
	end
	local session = sessions[userId]
	return if session then session.wallet else nil
end

-- Convenience guard for purchase flows: true only when the player can
-- afford `amount` of `currency`. Server-only. Not atomic — still rely on
-- minusMoney's result as the source of truth (it re-checks atomically).
function EconomyProvider.canAfford(userId: number, currency: CurrencyId, amount: number): boolean
	local balance = EconomyProvider.getBalance(userId, currency)
	return balance ~= nil and balance >= amount
end

-- Last synced balance for a currency on the client, or its configured
-- default if nothing has synced yet. Client-only. Always returns a number.
function EconomyProvider.getLocalBalance(currency: CurrencyId): number
	return getLocalBalance(currency)
end

-- Subscribes to balance changes on the client. `listener` is called as
-- listener(currency, balance) on every change. Returns an unsubscribe
-- function. Client-only.
function EconomyProvider.onBalanceChanged(listener: Listener): () -> ()
	table.insert(localListeners, listener)
	return function()
		local index = table.find(localListeners, listener)
		if index then
			table.remove(localListeners, index)
		end
	end
end

-- Mounts the built-in read-only currency panel and returns its ScreenGui.
-- Client-only. Called automatically on join; call again only if you
-- destroyed the previous one and want a fresh panel.
function EconomyProvider.mountWalletGui(): ScreenGui?
	if not RunService:IsClient() then
		warn("[EconomyProvider] mountWalletGui must be called from the client")
		return nil
	end
	return mountWalletGui()
end

--------------------------------------------------------------------------
-- Auto bootstrap — runs once, at require time, on whichever side loaded it
--------------------------------------------------------------------------

if IS_SERVER then
	-- Auto-save loop: periodically persist every active profile (which also
	-- refreshes its session-lock heartbeat). Snapshot the profiles first so a
	-- concurrent release (PlayerRemoving) can't mutate the set mid-iteration.
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			local snapshot: { Profile } = {}
			for _, profile in activeProfiles do
				table.insert(snapshot, profile)
			end
			for _, profile in snapshot do
				task.spawn(saveProfile, profile)
			end
		end
	end)

	-- BindToClose: final-save and unlock every active profile before the
	-- server dies. Roblox grants up to 30s here; wait for all releases.
	game:BindToClose(function()
		local userIds: { number } = {}
		for userId in activeProfiles do
			table.insert(userIds, userId)
		end

		local remaining = #userIds
		if remaining == 0 then
			return
		end

		for _, userId in userIds do
			task.spawn(function()
				releaseProfile(userId)
				remaining -= 1
			end)
		end

		while remaining > 0 do
			task.wait()
		end
	end)

	-- Answer client snapshot (re)requests using only server-authoritative
	-- state. Any arguments the client sends are ignored — the request
	-- carries no trust.
	remote.OnServerEvent:Connect(function(player: Player)
		local session = sessions[player.UserId]
		if session then
			syncFull(player, session.wallet)
		end
	end)

	local function onPlayerAdded(player: Player)
		local profile = loadProfileAsync(player.UserId)
		if not profile then
			player:Kick("Your economy data is busy on another server. Please rejoin in a moment.")
			return
		end

		-- The player may have left while the DataStore call yielded; release
		-- the lock we just took rather than leaking it.
		if player.Parent ~= Players then
			releaseProfile(player.UserId)
			return
		end

		bindSession(player, profile)
	end

	local function onPlayerRemoving(player: Player)
		unbindSession(player.UserId)
		releaseProfile(player.UserId)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	print("[EconomyProvider] server online with base currencies: coin, copper, silver, gold")
else
	-- Server is the only legitimate sender. The payload shape is still
	-- validated so a malformed message can never error the UI; the client
	-- never writes back, since it is strictly read-only.
	remote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.kind == "full" then
			if type(payload.wallet) == "table" then
				applyFull(payload.wallet)
			end
		elseif payload.kind == "update" then
			if type(payload.currency) == "string" and type(payload.balance) == "number" then
				applyUpdate(payload.currency, payload.balance)
			end
		end
	end)

	-- Build the read-only currency panel immediately. It renders configured
	-- defaults until the first snapshot arrives, then refreshes from synced
	-- values.
	mountWalletGui()

	-- Request the current snapshot in case listening started after the
	-- server's initial push. The request sends no data; the server replies
	-- from its own authoritative state.
	remote:FireServer()

	print("[EconomyProvider] client online (read-only)")
end

return EconomyProvider
