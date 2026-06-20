--!strict
-- Centralised constants shared across server and client. Keeping these in
-- Shared prevents magic strings from drifting between the in-house
-- persistence layer and the RemoteEvent replication layer.

local Constants = {
	-- DataStore name for player economy profiles, read by the custom
	-- session-locked wrapper (ProfileStore).
	DATASTORE_NAME = "EconomyProfiles_v1",

	-- Prefix for per-player DataStore keys: PROFILE_KEY_PREFIX .. userId.
	PROFILE_KEY_PREFIX = "Player_",

	-- Name of the RemoteEvent the server creates in ReplicatedStorage.Shared
	-- to push wallet state to clients. The client waits for this same name.
	WALLET_SYNC_EVENT = "WalletSyncEvent",

	-- Session locking: a profile's lock is considered stale (and may be
	-- stolen by another server) once its heartbeat is older than this many
	-- seconds. The auto-save loop refreshes the heartbeat well within the
	-- window, so a live server never loses its lock; only a crashed one does.
	SESSION_LOCK_EXPIRE = 600,

	-- How often (seconds) active profiles are auto-saved and their session
	-- lock heartbeat refreshed. Must stay comfortably below SESSION_LOCK_EXPIRE.
	AUTO_SAVE_INTERVAL = 60,

	-- DataStore call resilience. Failed UpdateAsync calls are retried with
	-- exponential backoff: RETRY_BASE * 2^(attempt-1) seconds.
	DATASTORE_MAX_RETRIES = 4,
	DATASTORE_RETRY_BASE = 1,

	-- Acquiring a session lock contended by another live server is retried a
	-- few times (e.g. to let a server-hop release complete) before giving up.
	LOCK_ACQUIRE_ATTEMPTS = 5,
	LOCK_ACQUIRE_DELAY = 2,

	-- Mutation bounds enforced by the server before touching any balance.
	-- Roblox doubles lose integer precision beyond 2^53; we stay well under.
	MIN_BALANCE = 0,
	MAX_SAFE_AMOUNT = 2 ^ 53 - 1,
}

table.freeze(Constants)

return Constants
