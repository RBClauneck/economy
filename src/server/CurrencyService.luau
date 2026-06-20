--!strict
-- CurrencyService is the core server-side economy API. Other server modules
-- (Market, Trading, Rewards) call into it to mutate player balances. It is
-- the ONLY place balances are written.
--
-- Data flow (per the economy-core ladder):
--   1. Validate the argument (Validation module).
--   2. Mutate the authoritative in-memory wallet (the loaded Profile's data).
--   3. Persistence is owned by ProfileStore (custom session-locked wrapper),
--      which auto-saves the same in-memory table on an interval and on release.
--   4. Sync the change to the client via the WalletSyncEvent RemoteEvent.
--
-- The client is strictly read-only; it never calls these functions. They are
-- exposed to trusted server callers only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.Types)
local CurrencyConfig = require(Shared.CurrencyConfig)
local Validation = require(script.Parent.Validation)
local ProfileStore = require(script.Parent.ProfileStore)
local Replication = require(script.Parent.Replication)

type CurrencyId = Types.CurrencyId
type Wallet = Types.Wallet
type MutationResult = Types.MutationResult

-- A loaded player session: the owning Player (for replication) and the
-- session-locked Profile whose `data.wallet` is the authoritative balance set.
type Session = {
	player: Player,
	profile: ProfileStore.Profile,
	wallet: Wallet,
}

local CurrencyService = {}

-- userId -> Session. Only present while the player is in-game.
local sessions: { [number]: Session } = {}

-- Registers a player's loaded session. Called by the bootstrap once
-- ProfileStore has session-locked the profile. Missing currencies (e.g. a
-- custom currency added since last login) are back-filled with their default
-- so wallets stay complete, then the full wallet is pushed to the client.
function CurrencyService.bindSession(player: Player, profile: ProfileStore.Profile)
	local wallet: Wallet = profile.data.wallet or CurrencyConfig.buildDefaultWallet()
	for _, definition in CurrencyConfig.all() do
		if wallet[definition.id] == nil then
			wallet[definition.id] = definition.default
		end
	end
	profile.data.wallet = wallet

	sessions[player.UserId] = { player = player, profile = profile, wallet = wallet }
	Replication.syncFull(player, wallet)
end

-- Removes a session from memory. ProfileStore performs the final save/unlock
-- on release; this only drops the in-memory reference.
function CurrencyService.unbindSession(userId: number)
	sessions[userId] = nil
end

-- Reads a single balance. Returns nil if the player has no session or the
-- currency is unknown.
function CurrencyService.getBalance(userId: number, currency: CurrencyId): number?
	local session = sessions[userId]
	if not session then
		return nil
	end
	return session.wallet[currency]
end

-- Returns the player's whole wallet (server-authoritative), or nil if they
-- have no active session. Used to answer client snapshot requests.
function CurrencyService.getWallet(userId: number): Wallet?
	local session = sessions[userId]
	return if session then session.wallet else nil
end

-- Internal: applies a signed delta to a balance after full validation, then
-- replicates. `sign` is +1 for add, -1 for subtract. The mutated wallet is the
-- same table held by the Profile, so ProfileStore persists it automatically.
local function applyDelta(userId: number, currency: CurrencyId, amount: number, sign: number): MutationResult
	local session = sessions[userId]
	if not session then
		return { ok = false, reason = "no active session for player" }
	end

	local definition = CurrencyConfig.get(currency)
	if not definition then
		return { ok = false, reason = string.format("unknown currency '%s'", tostring(currency)) }
	end

	local amountOk, amountReason = Validation.checkAmount(amount)
	if not amountOk then
		return { ok = false, reason = amountReason }
	end

	local current = session.wallet[currency] or definition.default
	local result = current + (sign * amount)

	local resultOk, resultReason = Validation.checkResult(result, definition.max)
	if not resultOk then
		return { ok = false, reason = resultReason }
	end

	-- Step 2: authoritative in-memory mutation (also updates Profile.data.wallet,
	-- which is the same table, so the next auto-save persists it).
	session.wallet[currency] = result
	-- Step 4: replicate the single changed balance to the owning client.
	Replication.syncUpdate(session.player, currency, result)

	return { ok = true, balance = result }
end

-- Adds `amount` of `currency` to the player. Validates against overflow and
-- the currency ceiling. Safe for any trusted server caller.
function CurrencyService.addMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return applyDelta(userId, currency, amount, 1)
end

-- Removes `amount` of `currency` from the player. Fails (without mutating)
-- when the player lacks sufficient funds.
function CurrencyService.minusMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return applyDelta(userId, currency, amount, -1)
end

-- Convenience guard for purchase flows: returns true only when the player can
-- afford `amount` of `currency`. Callers should still rely on minusMoney's
-- result, which re-checks atomically, as the source of truth.
function CurrencyService.canAfford(userId: number, currency: CurrencyId, amount: number): boolean
	local balance = CurrencyService.getBalance(userId, currency)
	return balance ~= nil and balance >= amount
end

return CurrencyService
