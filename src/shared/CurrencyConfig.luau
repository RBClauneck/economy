--!strict
-- CurrencyConfig is the single source of truth for which currencies exist
-- in the economy. It ships with the four base currencies and exposes a
-- registration API so games can declare additional custom currencies at
-- boot time, before any player profile is loaded.
--
-- Both the server (to seed/validate wallets) and the client (to label UI)
-- read this config, so it lives in Shared.

local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Constants)

type CurrencyId = Types.CurrencyId
type CurrencyDefinition = Types.CurrencyDefinition

local CurrencyConfig = {}

-- The four built-in base currencies. Ordered from lowest to highest value
-- by convention; the order has no runtime meaning beyond UI display.
local BASE_CURRENCIES: { CurrencyDefinition } = {
	{ id = "coin", displayName = "Coin", abbreviation = "C", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "copper", displayName = "Copper", abbreviation = "Cu", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "silver", displayName = "Silver", abbreviation = "Ag", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "gold", displayName = "Gold", abbreviation = "Au", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
}

-- Internal registry keyed by CurrencyId. Seeded with the base currencies.
local registry: { [CurrencyId]: CurrencyDefinition } = {}
for _, definition in BASE_CURRENCIES do
	registry[definition.id] = definition
end

-- Optional fields a caller may supply when registering a custom currency.
export type CustomCurrencyOptions = {
	id: CurrencyId,
	displayName: string?,
	abbreviation: string?,
	default: number?,
	max: number?,
}

-- Registers a custom currency. Must be called during boot (before profiles
-- load) so every wallet is seeded consistently. Returns the frozen
-- definition that was stored.
function CurrencyConfig.register(options: CustomCurrencyOptions): CurrencyDefinition
	assert(type(options) == "table", "register expects an options table")

	local id = options.id
	assert(type(id) == "string" and #id > 0, "currency id must be a non-empty string")
	assert(id == string.lower(id), "currency id must be lowercase")
	assert(registry[id] == nil, string.format("currency '%s' is already registered", id))

	local default = options.default or 0
	local max = options.max or Constants.MAX_SAFE_AMOUNT
	assert(default >= Constants.MIN_BALANCE, "default balance cannot be negative")
	assert(max >= default, "max must be greater than or equal to default")

	local definition: CurrencyDefinition = {
		id = id,
		displayName = options.displayName or id,
		abbreviation = options.abbreviation or string.upper(string.sub(id, 1, 1)),
		default = default,
		max = max,
		isBase = false,
	}

	registry[id] = table.freeze(definition)
	return definition
end

-- Returns the definition for a currency, or nil if it is not registered.
function CurrencyConfig.get(id: CurrencyId): CurrencyDefinition?
	return registry[id]
end

-- Returns true when a currency id is known to the system.
function CurrencyConfig.exists(id: CurrencyId): boolean
	return registry[id] ~= nil
end

-- Returns a fresh array of every registered definition (a copy, so callers
-- cannot mutate the registry through it).
function CurrencyConfig.all(): { CurrencyDefinition }
	local list: { CurrencyDefinition } = {}
	for _, definition in registry do
		table.insert(list, definition)
	end
	return list
end

-- Builds a default wallet seeded with every registered currency's starting
-- balance. Used when a brand new player profile is created.
function CurrencyConfig.buildDefaultWallet(): Types.Wallet
	local wallet: Types.Wallet = {}
	for id, definition in registry do
		wallet[id] = definition.default
	end
	return wallet
end

return CurrencyConfig
