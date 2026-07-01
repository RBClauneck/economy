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

-- The full persisted payload for one player, written through the in-house
-- session-locked DataStore wrapper. Extend this as the economy grows; the
-- wrapper reconciles missing fields against the configured default.
export type ProfileData = {
	wallet: Wallet,
}

-- Messages sent Server -> Client over the WalletSyncEvent RemoteEvent. A
-- tagged union: "full" seeds the entire wallet on join, "update" carries a
-- single changed balance. The client treats every payload as read-only.
export type WalletSyncPayload =
	{ kind: "full", wallet: Wallet }
	| { kind: "update", currency: CurrencyId, balance: number }

return nil
