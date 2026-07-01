--!strict
-- EconomyProvider is the one file trusted server modules (Market, Trading,
-- Rewards, ...) require to use the economy. It is a thin facade over the
-- library's internal modules (CurrencyService, CurrencyConfig) so callers
-- never need to know that persistence, replication, and validation live in
-- separate files — they call a function here and the library does the rest.
--
-- Client is zero trust: everything below only makes sense as a server-side
-- call. The client never requires this module; it reads state through
-- WalletController instead (see src/client/WalletController.luau) and the
-- server remains the only side that ever decides a balance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared")

local CurrencyConfig = require(EconomyShared:WaitForChild("CurrencyConfig"))
local Types = require(EconomyShared:WaitForChild("Types"))
local CurrencyService = require(script.Parent:WaitForChild("CurrencyService"))

type CurrencyId = Types.CurrencyId
type Wallet = Types.Wallet
type MutationResult = Types.MutationResult
type CurrencyDefinition = Types.CurrencyDefinition
type CustomCurrencyOptions = CurrencyConfig.CustomCurrencyOptions

local EconomyProvider = {}

-- Adds `amount` of `currency` to the player. Validated against overflow and
-- the currency ceiling. Safe for any trusted server caller.
function EconomyProvider.addMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return CurrencyService.addMoney(userId, currency, amount)
end

-- Removes `amount` of `currency`. Fails (without mutating) when the player
-- lacks sufficient funds.
function EconomyProvider.minusMoney(userId: number, currency: CurrencyId, amount: number): MutationResult
	return CurrencyService.minusMoney(userId, currency, amount)
end

-- Reads a single balance. Returns nil if the player has no session or the
-- currency is unknown.
function EconomyProvider.getBalance(userId: number, currency: CurrencyId): number?
	return CurrencyService.getBalance(userId, currency)
end

-- Returns the player's whole wallet, or nil if they have no active session.
function EconomyProvider.getWallet(userId: number): Wallet?
	return CurrencyService.getWallet(userId)
end

-- Convenience guard for purchase flows: true only when the player can
-- afford `amount` of `currency`. Not atomic — still rely on minusMoney's
-- result as the source of truth (it re-checks atomically).
function EconomyProvider.canAfford(userId: number, currency: CurrencyId, amount: number): boolean
	return CurrencyService.canAfford(userId, currency, amount)
end

-- Registers a custom currency. Must be called at boot, before any profile
-- loads. Also register the same currency on the client so the UI can label
-- it (see wiki/API.md).
function EconomyProvider.registerCurrency(options: CustomCurrencyOptions): CurrencyDefinition
	return CurrencyConfig.register(options)
end

function EconomyProvider.getCurrencyDefinition(id: CurrencyId): CurrencyDefinition?
	return CurrencyConfig.get(id)
end

function EconomyProvider.getAllCurrencies(): { CurrencyDefinition }
	return CurrencyConfig.all()
end

return EconomyProvider
