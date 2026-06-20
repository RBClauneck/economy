--!strict
-- Replication owns the Server -> Client wallet sync over a standard Roblox
-- RemoteEvent. It replaces the former third-party ReplicaService dependency.
--
-- The server creates a single WalletSyncEvent inside ReplicatedStorage.EconomyShared
-- (so it replicates to every client by name) and is the ONLY side that ever
-- calls FireClient. The client never sends balance data; the one inbound
-- message it may send is a no-argument "resend my snapshot" request, which is
-- read-only and answered purely from server-authoritative state. This keeps
-- the server the sole dictator of balances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared")

local Types = require(EconomyShared:WaitForChild("Types"))
local Constants = require(EconomyShared:WaitForChild("Constants"))

type Wallet = Types.Wallet
type CurrencyId = Types.CurrencyId
type WalletSyncPayload = Types.WalletSyncPayload

local Replication = {}

-- Create the RemoteEvent up front so it exists before any client requests it.
local existing = EconomyShared:FindFirstChild(Constants.WALLET_SYNC_EVENT)
local walletSync: RemoteEvent
if existing and existing:IsA("RemoteEvent") then
	walletSync = existing
else
	walletSync = Instance.new("RemoteEvent")
	walletSync.Name = Constants.WALLET_SYNC_EVENT
	walletSync.Parent = EconomyShared
end

-- Pushes the player's entire wallet (used on join / on request).
function Replication.syncFull(player: Player, wallet: Wallet)
	local payload: WalletSyncPayload = { kind = "full", wallet = wallet }
	walletSync:FireClient(player, payload)
end

-- Pushes a single changed balance (used after every mutation).
function Replication.syncUpdate(player: Player, currency: CurrencyId, balance: number)
	local payload: WalletSyncPayload = { kind = "update", currency = currency, balance = balance }
	walletSync:FireClient(player, payload)
end

-- Wires the inbound snapshot request. `resolver` returns the requesting
-- player's authoritative wallet (or nil if they have no active session). Any
-- arguments the client sends are ignored — the request carries no trust.
function Replication.onRequest(resolver: (player: Player) -> Wallet?)
	walletSync.OnServerEvent:Connect(function(player: Player)
		local wallet = resolver(player)
		if wallet then
			Replication.syncFull(player, wallet)
		end
	end)
end

return Replication
