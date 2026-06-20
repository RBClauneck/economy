--!strict
-- WalletController is the read-only client view of the player's wallet. It
-- observes the ReplicaService replica created by the server and exposes the
-- replicated balances plus a change signal for UI to subscribe to.
--
-- This module contains NO mutation logic. The client never requests economy
-- changes; it only reflects what the server has already decided. All values
-- here are treated as strictly read-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.Types)
local CurrencyConfig = require(Shared.CurrencyConfig)

type CurrencyId = Types.CurrencyId
type Wallet = Types.Wallet

local WalletController = {}

-- Local mirror of the replicated wallet. Updated only from replica events.
local wallet: Wallet = {}

-- Listeners notified whenever a balance changes: (currency, newBalance).
type Listener = (CurrencyId, number) -> ()
local listeners: { Listener } = {}

local function notify(currency: CurrencyId, balance: number)
	for _, listener in listeners do
		task.spawn(listener, currency, balance)
	end
end

-- Returns the last replicated balance for a currency, or its configured
-- default if nothing has replicated yet.
function WalletController.getBalance(currency: CurrencyId): number
	local value = wallet[currency]
	if value ~= nil then
		return value
	end
	local definition = CurrencyConfig.get(currency)
	return if definition then definition.default else 0
end

-- Subscribes a listener to balance changes. Returns an unsubscribe function.
function WalletController.onChanged(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

-- Binds the controller to a ReplicaController replica. Called once the
-- client-side ReplicaController reports the PlayerWallet replica. Seeds the
-- local mirror and wires per-key change listening.
function WalletController.bind(replica: any)
	-- Seed the local mirror and push the initial values out so any UI created
	-- before the replica arrived (e.g. the wallet GUI) renders real balances.
	for currency, balance in replica.Data.wallet do
		wallet[currency] = balance
		notify(currency, balance)
	end

	replica:ListenToWrite({ "wallet" }, function(currency: CurrencyId, balance: number)
		wallet[currency] = balance
		notify(currency, balance)
	end)
end

return WalletController
