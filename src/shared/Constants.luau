--!strict
-- Centralised constants shared across server and client. Keeping these in
-- Shared prevents magic strings from drifting between the persistence layer
-- and the replication layer.

local Constants = {
	-- DataKeep store identifier for player economy profiles.
	DATASTORE_NAME = "EconomyProfiles_v1",

	-- ReplicaService class token used to replicate a player's wallet.
	WALLET_REPLICA_CLASS = "PlayerWallet",

	-- Mutation bounds enforced by the server before touching any balance.
	-- Roblox doubles lose integer precision beyond 2^53; we stay well under.
	MIN_BALANCE = 0,
	MAX_SAFE_AMOUNT = 2 ^ 53 - 1,
}

table.freeze(Constants)

return Constants
