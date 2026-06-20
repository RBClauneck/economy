# Economy Library — API Reference

> **Self-contained integration guide.** This document is the single source of
> truth for consuming the RBClauneck Economy library from another place/project
> (typically vendored at `packages/economy`). It describes every public module,
> function, type, and event the library exposes, plus the runtime locations and
> integration steps. **You should not need to read the library's source to use
> it — everything you need is here.**

- **Library:** `RBClauneck/economy`
- **Language:** Luau (Roblox), `--!strict`
- **Build tool:** Rojo (`rojo-rbx/rojo@7.7.0-rc.1`, via `aftman.toml`)
- **Dependencies:** none (in-house persistence + standard RemoteEvents)

---

## 1. Architecture at a glance

The economy is a **server-authoritative** currency system with a strictly
**read-only client**.

```
 trusted server modules (Market, Trading, Rewards, ...)
            │  addMoney / minusMoney / getBalance / canAfford
            ▼
   ┌──────────────────────┐      writes balances        ┌─────────────────┐
   │   CurrencyService     │ ──────────────────────────▶ │  in-memory      │
   │  (server core API)    │                              │  Wallet (Profile)│
   └──────────┬───────────┘                              └────────┬────────┘
              │ validate (Validation)                             │ auto-save / BindToClose
              │ replicate (Replication)                           ▼
              │                                          ┌─────────────────┐
              │                                          │  ProfileStore    │
              │                                          │ session-locked   │
              │                                          │ DataStore wrapper│
              ▼                                          └─────────────────┘
   WalletSyncEvent (RemoteEvent, Server ▶ Client only)
              │
              ▼
   ┌──────────────────────┐   onChanged / getBalance   ┌─────────────────┐
   │   WalletController    │ ─────────────────────────▶ │   WalletGui      │
   │ (read-only client)    │                            │ (read-only UI)   │
   └──────────────────────┘                            └─────────────────┘
```

**Golden rules for consumers**

1. **All balance mutations happen on the server**, only through `CurrencyService`.
2. **The client is read-only.** It observes state via `WalletController`; it
   never requests mutations. The only client→server message is a no-argument
   "resend my snapshot" request, answered purely from server state.
3. **Register custom currencies at boot**, before any player profile loads.
4. Every mutation is validated (NaN, infinity, negative, non-integer, overflow,
   per-currency ceiling) and returns a `MutationResult` — branch on `.ok`, do
   not rely on raised errors.

---

## 2. Runtime locations (where modules live)

The library's own `default.project.json` maps the source folders into the
DataModel as follows. **Inside the library, modules reference each other
through these runtime paths** — most importantly the shared folder, which is
always at `ReplicatedStorage.EconomyShared`:

| Source folder | Runtime location | Notes |
| :--- | :--- | :--- |
| `src/shared` | `ReplicatedStorage.EconomyShared` | Constants, Types, CurrencyConfig (server **and** client read this) |
| `src/server` | `ServerScriptService.Server` | Bootstrap + core API |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | Bootstrap + read-only UI |

> **Vendoring as `packages/economy`:** when you integrate this repo as a
> submodule/package, route the three source folders to the locations above in
> your host project's Rojo project file (or `$path` includes). The shared
> folder **must** end up at `ReplicatedStorage.EconomyShared` — the library
> hard-codes that path. The server/client folder *names* may differ in your
> tree; only the require paths shown below matter.

Acquire the shared folder from any script with:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyShared = ReplicatedStorage:WaitForChild("EconomyShared") -- client
-- or ReplicatedStorage.EconomyShared on the server (it exists at boot)
```

---

## 3. Server API — `CurrencyService`

The **only** place balances are written. Require it from your server modules:

```lua
local CurrencyService = require(ServerScriptService.Server.CurrencyService)
```

> Replace `ServerScriptService.Server` with wherever you mapped `src/server`.

All mutating calls return a `MutationResult` (see [§7](#7-types)).

### `CurrencyService.addMoney(userId, currency, amount) → MutationResult`

Adds `amount` of `currency` to the player. Validated against overflow and the
currency ceiling. Safe for any trusted server caller.

| Param | Type | Description |
| :--- | :--- | :--- |
| `userId` | `number` | Target player's `UserId`. |
| `currency` | `CurrencyId` (`string`) | Registered currency id, e.g. `"gold"`. |
| `amount` | `number` | Non-negative integer to add. |

```lua
local result = CurrencyService.addMoney(player.UserId, "gold", 50)
if result.ok then
    print("New gold balance:", result.balance)
else
    warn("Add failed:", result.reason)
end
```

### `CurrencyService.minusMoney(userId, currency, amount) → MutationResult`

Removes `amount` of `currency`. **Fails without mutating** when the player
lacks sufficient funds (`reason = "insufficient funds"`). Same params as
`addMoney`.

```lua
local result = CurrencyService.minusMoney(player.UserId, "coin", 10)
if not result.ok then
    -- e.g. "insufficient funds", "no active session for player"
    warn(result.reason)
end
```

### `CurrencyService.getBalance(userId, currency) → number?`

Reads a single balance. Returns `nil` if the player has no active session or
the currency is unknown.

```lua
local gold = CurrencyService.getBalance(player.UserId, "gold") or 0
```

### `CurrencyService.getWallet(userId) → Wallet?`

Returns the player's whole wallet (`{ [CurrencyId]: number }`), or `nil` if
they have no active session.

```lua
local wallet = CurrencyService.getWallet(player.UserId)
if wallet then
    for currency, balance in wallet do
        print(currency, balance)
    end
end
```

### `CurrencyService.canAfford(userId, currency, amount) → boolean`

Convenience guard for purchase flows: `true` only when the player can afford
`amount`. **Not atomic** — still rely on `minusMoney`'s result as the source of
truth (it re-checks atomically).

```lua
if CurrencyService.canAfford(player.UserId, "gold", price) then
    local result = CurrencyService.minusMoney(player.UserId, "gold", price)
    if result.ok then grantItem() end
end
```

### Session lifecycle (handled by the library bootstrap)

You normally do **not** call these — the library's `src/server` bootstrap wires
them into `Players.PlayerAdded` / `PlayerRemoving`. Documented for completeness:

| Function | Purpose |
| :--- | :--- |
| `CurrencyService.bindSession(player, profile)` | Registers a loaded session, back-fills missing currencies with their defaults, and pushes the full wallet to the client. |
| `CurrencyService.unbindSession(userId)` | Drops the in-memory session reference (final save/unlock is `ProfileStore`'s job). |

> **A balance only exists while the player has an active session.** All read/
> mutate calls return `nil`/`{ ok = false, reason = "no active session..." }`
> before the profile loads or after the player leaves.

---

## 4. Shared API — `CurrencyConfig`

Single source of truth for which currencies exist. Read by **both** server and
client. Require from the shared folder:

```lua
local CurrencyConfig = require(ReplicatedStorage.EconomyShared.CurrencyConfig)
```

### Base currencies (always present, no registration)

| id | displayName | abbreviation | default | max |
| :--- | :--- | :--- | :--- | :--- |
| `coin` | Coin | `C` | `0` | `MAX_SAFE_AMOUNT` |
| `copper` | Copper | `Cu` | `0` | `MAX_SAFE_AMOUNT` |
| `silver` | Silver | `Ag` | `0` | `MAX_SAFE_AMOUNT` |
| `gold` | Gold | `Au` | `0` | `MAX_SAFE_AMOUNT` |

### `CurrencyConfig.register(options) → CurrencyDefinition`

Registers a **custom currency**. Must be called **at boot, before any profile
loads** (so every wallet is seeded consistently). Returns the frozen
definition. Asserts (raises) on invalid input.

`options: CustomCurrencyOptions`

| Field | Type | Required | Default | Rules |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `string` | ✅ | — | Non-empty, **lowercase**, not already registered. |
| `displayName` | `string` | — | `id` | Human-readable label. |
| `abbreviation` | `string` | — | first char of `id`, upper | Short UI label. |
| `default` | `number` | — | `0` | `>= 0`. Starting balance for new profiles. |
| `max` | `number` | — | `MAX_SAFE_AMOUNT` | `>= default`. Hard mutation ceiling. |

```lua
-- At boot, in a server script that runs before the economy bootstrap (or in
-- the bootstrap itself):
CurrencyConfig.register({
    id = "gem",
    displayName = "Gem",
    abbreviation = "Gm",
    max = 1_000_000,
})
```

> **Important:** the client must register the same custom currencies as the
> server for the UI to label them. Register from a script that runs on both
> sides (e.g. a shared boot module), or ensure the client also registers them.
> Currencies missing on the client fall back to default labels/values.

### `CurrencyConfig.get(id) → CurrencyDefinition?`

Returns the definition for a currency, or `nil` if not registered.

### `CurrencyConfig.exists(id) → boolean`

`true` when the currency id is known.

### `CurrencyConfig.all() → { CurrencyDefinition }`

Returns the shared, **insertion-ordered** list of every registered definition
(base currencies first, then customs in registration order). The returned array
and its definitions are frozen — iterate, never mutate.

```lua
for _, def in CurrencyConfig.all() do
    print(def.displayName, def.abbreviation, def.default, def.max)
end
```

### `CurrencyConfig.buildDefaultWallet() → Wallet`

Builds a fresh wallet seeded with every registered currency's `default`. Used
by the library when creating a brand-new profile.

---

## 5. Client API — `WalletController` (read-only)

The read-only client mirror of the player's wallet, fed by the library's
client bootstrap from the `WalletSyncEvent`. Require from your client folder:

```lua
local WalletController = require(StarterPlayer.StarterPlayerScripts.Client.WalletController)
```

> Replace the path with wherever you mapped `src/client`. **Contains no
> mutation or networking** — it only reflects server-decided state.

### `WalletController.getBalance(currency) → number`

Last synced balance for a currency, or its configured `default` if nothing has
synced yet. Always returns a number (never `nil`).

```lua
local gold = WalletController.getBalance("gold")
```

### `WalletController.onChanged(listener) → unsubscribe`

Subscribes to balance changes. `listener` is called as
`listener(currency: CurrencyId, balance: number)` on every change (each
listener runs in its own `task.spawn`). Returns an unsubscribe function.

```lua
local disconnect = WalletController.onChanged(function(currency, balance)
    print(currency, "is now", balance)
end)
-- later:
disconnect()
```

### `WalletController.applyFull(snapshot)` / `applyUpdate(currency, balance)`

Fed by the client bootstrap from incoming sync payloads; you normally don't
call these. `applyFull` seeds an entire `Wallet` snapshot (join / on request);
`applyUpdate` applies one changed balance. Both notify `onChanged` listeners.

---

## 6. Replication & the `WalletSyncEvent`

Server→Client wallet sync rides a single `RemoteEvent` named **`WalletSyncEvent`**
created by the server inside `ReplicatedStorage.EconomyShared`.

- The **server is the only side that calls `FireClient`.**
- The client may fire the event **with no arguments** to request a fresh
  snapshot; the server answers from authoritative state and ignores any data
  the client sends.
- Payloads are a tagged union, `WalletSyncPayload` (see [§7](#7-types)).

Server-side `Replication` module (used by the bootstrap; documented for
completeness):

| Function | Purpose |
| :--- | :--- |
| `Replication.syncFull(player, wallet)` | Pushes the player's entire wallet (`kind = "full"`). |
| `Replication.syncUpdate(player, currency, balance)` | Pushes a single changed balance (`kind = "update"`). |
| `Replication.onRequest(resolver)` | Wires the inbound snapshot request; `resolver(player) → Wallet?` returns the player's authoritative wallet. |

> If you build your own custom UI instead of `WalletGui`, prefer consuming
> `WalletController` (§5) rather than connecting to `WalletSyncEvent` directly —
> the controller already validates and mirrors state for you.

---

## 7. Types

Defined in `ReplicatedStorage.EconomyShared.Types`. Import with:

```lua
local Types = require(ReplicatedStorage.EconomyShared.Types)
type Wallet = Types.Wallet
```

```lua
-- Canonical lowercase key addressing a currency everywhere.
export type CurrencyId = string

-- Immutable description of a currency, registered once at boot.
export type CurrencyDefinition = {
    id: CurrencyId,        -- canonical key, e.g. "gold"
    displayName: string,   -- human label, e.g. "Gold"
    abbreviation: string,  -- short UI label, e.g. "Au"
    default: number,       -- starting balance for a fresh profile
    max: number,           -- hard ceiling enforced on every mutation
    isBase: boolean,       -- true for the four built-in base currencies
}

-- Player balances: every known CurrencyId → non-negative integer.
export type Wallet = { [CurrencyId]: number }

-- Returned by every mutating call. Branch on `ok`; do not rely on errors.
export type MutationResult = {
    ok: boolean,
    balance: number?,  -- new balance when ok == true
    reason: string?,   -- failure reason when ok == false
}

-- Full persisted payload for one player (extensible; the store reconciles
-- missing fields against the configured default).
export type ProfileData = {
    wallet: Wallet,
}

-- Server → Client messages over WalletSyncEvent (read-only on the client).
export type WalletSyncPayload =
    { kind: "full", wallet: Wallet }
    | { kind: "update", currency: CurrencyId, balance: number }
```

`CurrencyConfig` additionally exports the registration options type:

```lua
export type CustomCurrencyOptions = {
    id: CurrencyId,
    displayName: string?,
    abbreviation: string?,
    default: number?,
    max: number?,
}
```

### `MutationResult.reason` values

| `reason` | Cause |
| :--- | :--- |
| `"no active session for player"` | Player has no loaded profile (not in-game / not yet loaded). |
| `"unknown currency '<id>'"` | Currency not registered. |
| `"amount must be a number"` | `amount` wasn't a number. |
| `"amount is NaN"` | `amount` was `NaN`. |
| `"amount is infinite"` | `amount` was ±∞. |
| `"amount must be non-negative"` | `amount < 0`. |
| `"amount must be an integer"` | `amount` had a fractional part. |
| `"amount exceeds maximum safe value"` | `amount > MAX_SAFE_AMOUNT`. |
| `"insufficient funds"` | Result would drop below `0` (on `minusMoney`). |
| `"balance exceeds currency maximum"` | Result would exceed the currency's `max`. |

---

## 8. Constants

Defined in `ReplicatedStorage.EconomyShared.Constants` (frozen table):

```lua
local Constants = require(ReplicatedStorage.EconomyShared.Constants)
```

| Constant | Value | Meaning |
| :--- | :--- | :--- |
| `DATASTORE_NAME` | `"EconomyProfiles_v1"` | DataStore name for player profiles. |
| `PROFILE_KEY_PREFIX` | `"Player_"` | Per-player key prefix (`Player_<userId>`). |
| `WALLET_SYNC_EVENT` | `"WalletSyncEvent"` | Name of the sync RemoteEvent. |
| `SESSION_LOCK_EXPIRE` | `600` | Seconds before a session lock is considered stale/stealable. |
| `AUTO_SAVE_INTERVAL` | `60` | Seconds between auto-saves (also refreshes the lock heartbeat). |
| `DATASTORE_MAX_RETRIES` | `4` | Max DataStore retry attempts. |
| `DATASTORE_RETRY_BASE` | `1` | Backoff base seconds (`base * 2^(attempt-1)`). |
| `LOCK_ACQUIRE_ATTEMPTS` | `5` | Retries when a lock is contended by another live server. |
| `LOCK_ACQUIRE_DELAY` | `2` | Seconds between lock-acquire retries. |
| `MIN_BALANCE` | `0` | Global balance floor. |
| `MAX_SAFE_AMOUNT` | `2^53 - 1` | Global ceiling (stays within double integer precision). |

---

## 9. Persistence — `ProfileStore` (internal)

`ProfileStore` (in `src/server`) is the in-house, **session-locked** DataStore
wrapper and the single owner of every DataStore call. You generally do not call
it directly; the bootstrap drives it. Key guarantees:

- **Session locking:** a profile can only be edited by one server at a time. A
  lock is "live" while `os.time() - heartbeat < SESSION_LOCK_EXPIRE`; the
  auto-save loop refreshes the heartbeat so a running server keeps ownership and
  a crashed server's lock goes stale and is reclaimed. Prevents two servers
  corrupting one profile.
- **Auto-save:** every active profile is persisted every `AUTO_SAVE_INTERVAL`
  seconds.
- **`BindToClose` durability:** all profiles are final-saved and unlocked before
  shutdown, so no in-flight balance change is lost on a restart.
- **Reconcile:** loaded profiles gain newly-added fields (e.g. a newly
  registered currency) without wiping existing data.

Reference signatures (advanced use only):

```lua
ProfileStore.setup(storeName: string, factory: () -> ProfileData)  -- boot config + starts loops
ProfileStore.loadAsync(userId: number): Profile?   -- nil if another live server holds the lock
ProfileStore.save(profile: Profile): boolean
ProfileStore.release(userId: number)               -- final save + unlock
-- export type Profile = { userId: number, key: string, data: ProfileData }
```

If `loadAsync` returns `nil`, the bootstrap kicks the player with:
*"Your economy data is busy on another server. Please rejoin in a moment."*

---

## 10. Integration checklist (host project)

1. **Vendor the library** (e.g. submodule at `packages/economy`):
   ```bash
   mkdir -p packages
   git submodule add https://github.com/RBClauneck/economy.git packages/economy
   ```
2. **Map the source folders** in your host Rojo project so that:
   - `packages/economy/src/shared` → `ReplicatedStorage.EconomyShared` *(required exact path)*
   - `packages/economy/src/server` → somewhere under `ServerScriptService`
   - `packages/economy/src/client` → somewhere under `StarterPlayer.StarterPlayerScripts`
3. **Ensure the bootstraps run.** `src/server/init.server.luau` and
   `src/client/init.client.luau` wire player lifecycle, persistence, replication
   and the read-only UI automatically.
4. **Register custom currencies at boot** (before profiles load), on both server
   and client, via `CurrencyConfig.register(...)`.
5. **Mutate balances only through `CurrencyService`** from trusted server
   modules; **read on the client only through `WalletController`**.

### End-to-end example

```lua
-- ── Server: a shop module ────────────────────────────────────────────────
local ServerScriptService = game:GetService("ServerScriptService")
local CurrencyService = require(ServerScriptService.Server.CurrencyService)

local function buy(player: Player, itemPrice: number)
    local result = CurrencyService.minusMoney(player.UserId, "gold", itemPrice)
    if result.ok then
        grantItem(player)
        return true
    end
    warn(("purchase failed for %s: %s"):format(player.Name, result.reason))
    return false
end
```

```lua
-- ── Client: react to balance changes ─────────────────────────────────────
local StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts
local WalletController = require(StarterPlayerScripts.Client.WalletController)

WalletController.onChanged(function(currency, balance)
    if currency == "gold" then
        updateGoldLabel(balance)
    end
end)
```

---

## 11. Quick reference

| I want to... | Use | Side |
| :--- | :--- | :--- |
| Give a player currency | `CurrencyService.addMoney(userId, id, amount)` | Server |
| Charge a player | `CurrencyService.minusMoney(userId, id, amount)` | Server |
| Check a server-side balance | `CurrencyService.getBalance(userId, id)` | Server |
| Get a player's full wallet | `CurrencyService.getWallet(userId)` | Server |
| Pre-check affordability | `CurrencyService.canAfford(userId, id, amount)` | Server |
| Add a new currency type | `CurrencyConfig.register({ id = ... })` (at boot) | Both |
| List all currencies | `CurrencyConfig.all()` | Both |
| Look up a currency's definition | `CurrencyConfig.get(id)` | Both |
| Read a balance for UI | `WalletController.getBalance(id)` | Client |
| React to balance changes | `WalletController.onChanged(fn)` | Client |
