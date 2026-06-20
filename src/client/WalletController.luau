--!strict
-- WalletController is the read-only client view of the player's wallet. It
-- holds the balances delivered over the WalletSyncEvent RemoteEvent and exposes
-- a change signal for UI to subscribe to.
--
-- This module contains NO mutation logic and no networking. The client never
-- requests economy changes; it only reflects what the server has already
-- decided. All values here are treated as strictly read-only. The bootstrap
-- (init.client) feeds applyFull/applyUpdate from the RemoteEvent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Types = require(Shared.Types)
local CurrencyConfig = require(Shared.CurrencyConfig)

type CurrencyId = Types.CurrencyId
type Wallet = Types.Wallet

local WalletController = {}

-- Local mirror of the wallet. Updated only from server sync messages.
local wallet: Wallet = {}

-- Listeners notified whenever a balance changes: (currency, newBalance).
type Listener = (CurrencyId, number) -> ()
local listeners: { Listener } = {}

local function notify(currency: CurrencyId, balance: number)
	for _, listener in listeners do
		task.spawn(listener, currency, balance)
	end
end

-- Returns the last synced balance for a currency, or its configured default
-- if nothing has synced yet.
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

-- Applies a full wallet snapshot from the server (the "full" sync payload sent
-- on join / on request). Seeds every balance and notifies listeners so UI
-- built before the snapshot arrived renders real balances.
function WalletController.applyFull(snapshot: Wallet)
	for currency, balance in snapshot do
		wallet[currency] = balance
		notify(currency, balance)
	end
end

-- Applies a single balance change from the server (the "update" sync payload
-- sent after every mutation).
function WalletController.applyUpdate(currency: CurrencyId, balance: number)
	wallet[currency] = balance
	notify(currency, balance)
end

return WalletController
