--!strict
-- CurrencyConfig is the single source of truth for which currencies exist
-- in the economy. It ships with the four base currencies and exposes a
-- registration API so games can declare additional custom currencies at
-- boot time, before any player profile is loaded.
--
-- Both the server (to seed/validate wallets) and the client (to label UI)
-- read this config, so it lives in Shared.
--
-- Currencies are only ever added at boot (register), never removed, so the
-- registry keeps a stable insertion-ordered array alongside the id->def map.
-- That lets get/exists stay O(1) while all() returns a deterministic order
-- without re-sorting on every call.

local Types = require(script.Parent.Types)
local Constants = require(script.Parent.Constants)

type CurrencyId = Types.CurrencyId
type CurrencyDefinition = Types.CurrencyDefinition

local CurrencyConfig = {}

-- The four built-in base currencies, lowest to highest value by convention.
local BASE_CURRENCIES: { CurrencyDefinition } = {
	{ id = "coin", displayName = "Coin", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "copper", displayName = "Copper", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "silver", displayName = "Silver", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
	{ id = "gold", displayName = "Gold", default = 0, max = Constants.MAX_SAFE_AMOUNT, isBase = true },
}

-- O(1) lookup map and insertion-ordered list. Kept in sync by `add`.
local byId: { [CurrencyId]: CurrencyDefinition } = {}
local ordered: { CurrencyDefinition } = {}

local function add(definition: CurrencyDefinition)
	byId[definition.id] = definition
	table.insert(ordered, definition)
end

for _, definition in BASE_CURRENCIES do
	add(table.freeze(definition))
end

-- Optional fields a caller may supply when registering a custom currency.
export type CustomCurrencyOptions = {
	id: CurrencyId,
	displayName: string?,
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
	assert(byId[id] == nil, string.format("currency '%s' is already registered", id))

	local default = options.default or 0
	local max = options.max or Constants.MAX_SAFE_AMOUNT
	assert(default >= Constants.MIN_BALANCE, "default balance cannot be negative")
	assert(max >= default, "max must be greater than or equal to default")

	local definition: CurrencyDefinition = table.freeze({
		id = id,
		displayName = options.displayName or id,
		default = default,
		max = max,
		isBase = false,
	})

	add(definition)
	return definition
end

-- Returns the definition for a currency, or nil if it is not registered.
function CurrencyConfig.get(id: CurrencyId): CurrencyDefinition?
	return byId[id]
end

-- Returns true when a currency id is known to the system.
function CurrencyConfig.exists(id: CurrencyId): boolean
	return byId[id] ~= nil
end

-- Returns the shared, insertion-ordered list of every registered definition.
-- Each definition is frozen, so exposing the array directly is safe and
-- avoids allocating a copy on every call (callers iterate, never mutate).
function CurrencyConfig.all(): { CurrencyDefinition }
	return ordered
end

-- Builds a default wallet seeded with every registered currency's starting
-- balance. Used when a brand new player profile is created.
function CurrencyConfig.buildDefaultWallet(): Types.Wallet
	local wallet: Types.Wallet = {}
	for _, definition in ordered do
		wallet[definition.id] = definition.default
	end
	return wallet
end

return CurrencyConfig
