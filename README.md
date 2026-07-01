# RBClauneck Economy Library

Welcome to the **RBClauneck Economy Library**. This project serves as the core internal economy API designed to be shared across all places within the RBClauneck organization. 

It is built with a secure, exploit-proof architecture, utilizing modern state synchronization to ensure flawless data consistency between the Roblox Server and Client.

## 🌟 Key Features

* **Internal Core API:** Acts as the central backend service for other server-side modules (e.g., Market, Trading) to safely mutate economy states.
* **In-House Persistence & State Sync:** Ships its own dependency-free stack — a **Custom Session-Locked DataStore Wrapper** (`ProfileStore`) for safe DataStore session locking, auto-save, and `BindToClose` durability, plus **Standard Roblox RemoteEvents** (`WalletSyncEvent`) for robust one-way (Server-to-Client) state synchronization.
* **Read-Only Client Separation:** Strict boundaries where the client side is designed to be purely read-only, existing solely to observe state changes and update the GUI.
* **Rojo Integration:** Fully configured with a `default.project.json` to automatically route modules to their correct Roblox DataModel locations (`ServerScriptService`, `StarterPlayerScripts`, and `ReplicatedStorage`).

## 📁 Project Structure

The repository is organized to support a modular and secure workflow:

* **`src/server/`** — Contains backend logic, the custom session-locked `ProfileStore` (DataStore wrapper), the `Replication` RemoteEvent layer, and the core internal API exposed to other server modules.
* **`src/client/`** — Contains frontend logic exclusively for reading synced data (received over the `WalletSyncEvent` RemoteEvent) and triggering UI updates.
* **`src/shared/`** — Contains shared resources acting as a bridge between the server and client, such as Constants, Types, Configs, and RemoteEvent definitions.
* **`aftman.toml`** — Manages cross-platform toolchains to ensure consistent versions of tools like Rojo (`rojo-rbx/rojo@7.7.0-rc.1`) across the entire team and CI/CD pipelines.

## 💰 Currency System

The economy ships with four **base currencies** — `coin`, `copper`, `silver`,
and `gold` — and supports registering additional **custom currencies** at boot.

* **Definitions** live in `src/shared/CurrencyConfig.luau`, the single source of
  truth read by both server and client.
* **Register a custom currency** before profiles load:

  ```lua
  local CurrencyConfig = require(ReplicatedStorage.Shared.CurrencyConfig)
  CurrencyConfig.register({ id = "gem", displayName = "Gem", max = 1_000_000 })
  ```

* **Mutate balances** from any trusted server module via the core API
  (`src/server/CurrencyService.luau`); every call is validated against NaN,
  infinities, negatives, non-integers, overflow and the per-currency ceiling:

  ```lua
  CurrencyService.addMoney(userId, "gold", 50)
  CurrencyService.minusMoney(userId, "coin", 10)
  ```

* **Read balances on the client** through the read-only
  `src/client/WalletController.luau`, which observes the replicated wallet and
  exposes an `onChanged` signal for UI.

## 🚀 Installation (For Place Repositories)

To integrate this library into your main place repository, add it as a Git submodule:

```bash
mkdir -p packages
git submodule add https://github.com/RBClauneck/economy.git packages/economy
