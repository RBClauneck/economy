--!strict
-- Economy client bootstrap.
--
-- Connects the read-only WalletController to the server's PlayerWallet replica
-- via ReplicaController. This side only observes and renders; it issues no
-- economy mutations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Constants = require(Shared.Constants)
local WalletController = require(script.WalletController)
local WalletGui = require(script.WalletGui)

-- Build the read-only currency panel immediately. It renders configured
-- defaults until the replica arrives, then refreshes from replicated values.
WalletGui.mount()

local Packages = ReplicatedStorage:FindFirstChild("Packages")
if not Packages then
	warn("[economy] Packages folder not found; wallet will not replicate")
	return
end

local ReplicaController = require(Packages:WaitForChild("ReplicaController")) :: any

ReplicaController.ReplicaOfClassCreated(Constants.WALLET_REPLICA_CLASS, function(replica: any)
	WalletController.bind(replica)
end)

ReplicaController.RequestData()

print("[economy] Wallet controller online (read-only)")
