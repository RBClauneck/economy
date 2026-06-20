--!strict
-- CurrencyService is the core server-side economy API. Other server modules
-- (Market, Trading, Rewards) call into it to mutate player balances. It is
-- the ONLY place balances are written.
--
-- Data flow (per the economy-core ladder):
--   1. Validate the argument (Validation module).
--   2. Mutate the authoritative in-memory wallet.
--   3. Persist through DataKeep (single store manager, no scattered calls).
--   4. Sync the new state to the client through ReplicaService.
--
-- The client is strictly read-only; it never calls these functions. They are
-- exposed to trusted server callers only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.Types)
local CurrencyConfig = require(Shared.CurrencyConfig)
local Constants = require(Shared.Constants)
local Validation = require(script.Parent.Validation)

type CurrencyId = Types.CurrencyId
type Wallet = Types.Wallet
type MutationResult = Types.MutationResult

-- A loaded player session: the authoritative wallet plus the persistence and
-- replication handles bound to it. Populated by onPlayerAdded, cleared by
-- onPlayerRemoving.
type Session = {
	wallet: Wallet,
	-- DataKeep profile/Keep handle. Typed loosely so this library does not
	-- hard-depend on a specific DataKeep version's exported types.
	keep: any,
	-- ReplicaService replica mirroring `wallet` to the owning client.
	replica: any,
}

local CurrencyService = {}

-- userId -> Session. Only present while the player is in-game.
local sessions: { [number]: Session } = {}

-- Registers a player's loaded session. Called by the bootstrap once DataKeep
-- has loaded the Keep and ReplicaService has created the replica. Missing
-- currencies (e.g. a custom currency added since last login) are back-filled
-- with their default so wallets stay complete.
function CurrencyService.bindSession(userId: number, keep: any, replica: any)
	local wallet: Wallet = keep.Data.wallet or CurrencyConfig.buildDefaultWallet()
	for _, definition in CurrencyConfig.all() do
		if wallet[definition.id] == nil then
			wallet[definition.id] = definition.default
		end
	end
	keep.Data.wallet = wallet
	sessions[userId] = { wallet = wallet, keep = keep, replica = replica }
end

-- Removes a session from memory. DataKeep is responsible for the final save
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

-- Internal: applies a signed delta to a balance after full validation, then
-- persists and replicates. `sign` is +1 for add, -1 for subtract.
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

	-- Step 2: authoritative in-memory mutation.
	session.wallet[currency] = result
	-- Step 3: persist. DataKeep saves session.keep.Data on its own cadence;
	-- writing the field keeps the queued snapshot current.
	session.keep.Data.wallet = session.wallet
	-- Step 4: replicate the single changed key to the owning client.
	session.replica:SetValue({ "wallet", currency }, result)

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
