--!strict
-- Economy server bootstrap.
--
-- Wires player lifecycle into the CurrencyService: on join, load the DataKeep
-- Keep and create the ReplicaService replica, then bind them as a session; on
-- leave, release persistence and drop the session.
--
-- DataKeep and ReplicaService are expected under ReplicatedStorage/Packages
-- (or wherever the host place vendors them). The requires are resolved lazily
-- so this library can be dropped into a place without the packages failing to
-- compile the rest of the economy core.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local CurrencyConfig = require(Shared.CurrencyConfig)
local Constants = require(Shared.Constants)
local CurrencyService = require(script.CurrencyService)

-- Example of declaring a custom currency at boot. Host places can register
-- their own currencies here (or before requiring this script) and they will
-- be seeded into every wallet automatically. Base currencies — coin, copper,
-- silver, gold — are always present without registration.
-- CurrencyConfig.register({ id = "gem", displayName = "Gem", abbreviation = "Gm", max = 1_000_000 })

local function onPlayerAdded(player: Player)
	-- Persistence (DataKeep) and replication (ReplicaService) are resolved by
	-- the host place. The economy core treats them as opaque handles and only
	-- relies on the contracts used in CurrencyService.
	local Packages = ReplicatedStorage:FindFirstChild("Packages")
	if not Packages then
		warn("[economy] Packages folder not found; cannot load profile for " .. player.Name)
		return
	end

	local DataKeep = require(Packages:WaitForChild("DataKeep")) :: any
	local ReplicaService = require(Packages:WaitForChild("ReplicaService")) :: any

	local store = DataKeep.GetStore(Constants.DATASTORE_NAME, {
		wallet = CurrencyConfig.buildDefaultWallet(),
	}):expect()

	local keep = store:LoadKeep("Player_" .. player.UserId):expect()
	if not keep then
		player:Kick("Economy profile failed to load. Please rejoin.")
		return
	end

	keep:Reconcile()
	keep.Releasing:Connect(function()
		player:Kick("Economy profile released. Please rejoin.")
	end)

	if player.Parent ~= Players then
		keep:Release()
		return
	end

	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken(Constants.WALLET_REPLICA_CLASS),
		Data = { wallet = keep.Data.wallet },
		Replication = player,
	})

	CurrencyService.bindSession(player.UserId, keep, replica)
end

local function onPlayerRemoving(player: Player)
	CurrencyService.unbindSession(player.UserId)
end

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

print("[economy] Currency service online with base currencies: coin, copper, silver, gold")
