--!strict
-- Economy client bootstrap.
--
-- Listens to the server's WalletSyncEvent RemoteEvent and feeds the read-only
-- WalletController, which the WalletGui renders. This side only observes; it
-- issues no economy mutations. No third-party packages are required.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared")

local Constants = require(EconomyShared.Constants)
local WalletController = require(script.WalletController)
local WalletGui = require(script.WalletGui)

-- Build the read-only currency panel immediately. It renders configured
-- defaults until the first snapshot arrives, then refreshes from synced values.
WalletGui.mount()

local walletSync = EconomyShared:WaitForChild(Constants.WALLET_SYNC_EVENT) :: RemoteEvent

-- Server is the only legitimate sender. We still validate the payload shape so
-- a malformed message can never error the UI, and we never write back: the
-- client is strictly read-only.
walletSync.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "full" then
		if type(payload.wallet) == "table" then
			WalletController.applyFull(payload.wallet)
		end
	elseif payload.kind == "update" then
		if type(payload.currency) == "string" and type(payload.balance) == "number" then
			WalletController.applyUpdate(payload.currency, payload.balance)
		end
	end
end)

-- Request the current snapshot in case we started listening after the server's
-- initial push. The request sends no data; the server replies from its own
-- authoritative state.
walletSync:FireServer()

print("[economy] Wallet controller online (read-only)")
