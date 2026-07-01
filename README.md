# RBClauneck Economy Library

Welcome to the **RBClauneck Economy Library**. This project serves as the core internal economy API designed to be shared across all places within the RBClauneck organization.

It is built with a secure, exploit-proof architecture, utilizing modern state synchronization to ensure flawless data consistency between the Roblox Server and Client.

## 🌟 Key Features

* **Single-File Package:** The entire library — persistence, replication, validation, currency registry, and the built-in wallet UI — ships as one drop-in ModuleScript, `EconomyProvider`. Require it and call its functions; there is no other code to wire up.
* **Function-Only API:** Every capability is a function on `EconomyProvider`. It detects whether it is running on the server or the client and bootstraps itself automatically — no setup calls, no manual RemoteEvent wiring, no separate server/client folders to maintain.
* **In-House Persistence & State Sync:** Ships its own dependency-free stack — a session-locked DataStore wrapper for safe session locking, auto-save, and `BindToClose` durability, plus a single Roblox RemoteEvent for robust one-way (Server-to-Client) state synchronization.
* **Read-Only Client Separation:** Strict boundaries where the client side is purely read-only, existing solely to observe state changes and update the built-in wallet GUI.

## 📁 Project Structure

* **`src/EconomyProvider.luau`** — The entire library: currency registry, validation, the session-locked persistence layer, replication, the server mutation API, the client wallet mirror, and the built-in wallet UI.
* **`default.project.json`** — Rojo project file mapping `src/EconomyProvider.luau` into `ReplicatedStorage`, where both the server and the client can require it.
* **`aftman.toml`** — Manages cross-platform toolchains to ensure consistent versions of tools like Rojo (`rojo-rbx/rojo@7.7.0-rc.1`) across the entire team and CI/CD pipelines.

## 💰 Currency System

The economy ships with four **base currencies** — `coin`, `copper`, `silver`,
and `gold` — and supports registering additional **custom currencies** at boot.

* **Register a custom currency** before any player joins, on both the server
  and the client so the client can label it:

  ```lua
  local EconomyProvider = require(ReplicatedStorage.EconomyProvider)
  EconomyProvider.registerCurrency({ id = "gem", displayName = "Gem", max = 1_000_000 })
  ```

* **Mutate balances** from any trusted server module; every call is validated
  against NaN, infinities, negatives, non-integers, overflow and the
  per-currency ceiling:

  ```lua
  EconomyProvider.addMoney(userId, "gold", 50)
  EconomyProvider.minusMoney(userId, "coin", 10)
  ```

* **Read balances on the client**:

  ```lua
  local gold = EconomyProvider.getLocalBalance("gold")
  EconomyProvider.onBalanceChanged(function(currency, balance)
      print(currency, "is now", balance)
  end)
  ```

## 🚀 Installation (For Place Repositories)

To integrate this library into your main place repository, add it as a Git submodule:

```bash
mkdir -p packages
git submodule add https://github.com/RBClauneck/economy.git packages/economy
```

Then map the single module into your host project's `default.project.json`,
anywhere under `ReplicatedStorage` so both the server and the client can
reach it:

```json
{
  "tree": {
    "ReplicatedStorage": {
      "EconomyProvider": {
        "$path": "packages/economy/src/EconomyProvider.luau"
      }
    }
  }
}
```

That's the entire integration. Require `ReplicatedStorage.EconomyProvider`
from any server or client script and call its functions — see
[`wiki/API.md`](wiki/API.md) for the full reference.
