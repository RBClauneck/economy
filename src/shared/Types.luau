--!strict
-- Shared type definitions for the RBClauneck Economy Library.
-- These types form the contract between the server core API and the
-- read-only client. They live in Shared so both sides agree on shape.

-- A CurrencyId is the canonical, lowercase key used to address a currency
-- everywhere in the system (storage, API arguments, replicated state).
export type CurrencyId = string

-- Static, immutable description of a single currency. Registered once at
-- boot through the CurrencyConfig and never mutated at runtime.
export type CurrencyDefinition = {
	id: CurrencyId, -- canonical key, e.g. "gold"
	displayName: string, -- human readable label, e.g. "Gold"
	abbreviation: string, -- short label for UI, e.g. "G"
	default: number, -- starting balance for a fresh profile
	max: number, -- hard ceiling enforced on every mutation
	isBase: boolean, -- true for the built-in base currencies
}

-- The persisted economy state for a single player. Maps every known
-- CurrencyId to a non-negative integer balance.
export type Wallet = { [CurrencyId]: number }

-- Result envelope returned by every mutating API call so callers can
-- branch on success without relying on raised errors.
export type MutationResult = {
	ok: boolean,
	balance: number?, -- new balance when ok == true
	reason: string?, -- failure reason when ok == false
}

return nil
