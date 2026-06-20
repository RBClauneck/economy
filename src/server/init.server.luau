--!strict
-- Economy server bootstrap.
--
-- Wires player lifecycle into the in-house persistence and replication stack:
--   - ProfileStore  : custom session-locked DataStore wrapper (auto-save +
--                     BindToClose live inside it).
--   - Replication   : standard RemoteEvent (WalletSyncEvent) for Server ->
--                     Client wallet sync.
--   - CurrencyService: the authoritative balance API.
--
-- No third-party packages are required; everything ships with the library.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared")

local CurrencyConfig = require(EconomyShared:WaitForChild("CurrencyConfig"))
local Constants = require(EconomyShared:WaitForChild("Constants"))
local CurrencyService = require(script:WaitForChild("CurrencyService"))
local ProfileStore = require(script:WaitForChild("ProfileStore"))
local Replication = require(script:WaitForChild("Replication"))

-- Example of declaring a custom currency at boot. Host places can register
-- their own currencies here (or before requiring this script) and they will
-- be seeded into every wallet automatically. Base currencies — coin, copper,
-- silver, gold — are always present without registration.
-- CurrencyConfig.register({ id = "gem", displayName = "Gem", max = 1_000_000 })

-- Configure the session-locked store with this library's default profile shape.
ProfileStore.setup(Constants.DATASTORE_NAME, function()
	return { wallet = CurrencyConfig.buildDefaultWallet() }
end)

-- Answer client snapshot (re)requests using only server-authoritative state.
Replication.onRequest(function(player: Player)
	return CurrencyService.getWallet(player.UserId)
end)

local function onPlayerAdded(player: Player)
	local profile = ProfileStore.loadAsync(player.UserId)
	if not profile then
		-- Another live server still holds the lock (or the DataStore is down).
		player:Kick("Your economy data is busy on another server. Please rejoin in a moment.")
		return
	end

	-- The player may have left while the DataStore call yielded; release the
	-- lock we just took rather than leaking it.
	if player.Parent ~= Players then
		ProfileStore.release(player.UserId)
		return
	end

	CurrencyService.bindSession(player, profile)
end

local function onPlayerRemoving(player: Player)
	CurrencyService.unbindSession(player.UserId)
	ProfileStore.release(player.UserId)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

print("[economy] Currency service online with base currencies: coin, copper, silver, gold")
