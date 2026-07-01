# Economy Library — API Reference

> **Self-contained integration guide.** This document is the single source of
> truth for consuming the RBClauneck Economy library from another place/project
> (typically vendored at `packages/economy`). It describes every function the
> library's single module exposes, plus the one integration step required.
> **You should not need to read the library's source to use it — everything
> you need is here.**

- **Library:** `RBClauneck/economy`
- **Language:** Luau (Roblox), `--!strict`
- **Build tool:** Rojo (`rojo-rbx/rojo@7.7.0-rc.1`, via `aftman.toml`)
- **Dependencies:** none (in-house persistence + a single standard RemoteEvent)
- **Shape:** one ModuleScript, `src/EconomyProvider.luau`, requireable from both the server and the client

---

## 1. Architecture at a glance

The economy is a **server-authoritative** currency system with a strictly
**read-only client**, packaged as a single drop-in `EconomyProvider` module.

```
 trusted server modules (Market, Trading, Rewards, ...)
            │  addMoney / minusMoney / getBalance / canAfford
            ▼
   ┌────────────────────────────────────────────────────────┐
   │                    EconomyProvider                       │
   │  (one ModuleScript; detects server vs. client on require) │
   │                                                            │
   │   server-side: session-locked DataStore persistence,      │
   │                validation, mutation API                   │
   │   client-side: read-only wallet mirror, built-in wallet UI │
   └───────────────────────────┬────────────────────────────┘
                                │ single RemoteEvent
                                │ (Server ▶ Client only)
                                ▼
                   getLocalBalance / onBalanceChanged
```

**Golden rules for consumers**

1. **All balance mutations happen on the server**, only through
   `EconomyProvider.addMoney` / `EconomyProvider.minusMoney`.
2. **The client is read-only.** It observes state via `getLocalBalance` /
   `onBalanceChanged`; it never requests mutations. The only client→server
   message is a no-argument "resend my snapshot" request, answered purely
   from server state.
3. **Register custom currencies at boot**, before any player profile loads,
   on both the server and the client.
4. Every mutation is validated (NaN, infinity, negative, non-integer, overflow,
   per-currency ceiling) and returns a `MutationResult` — branch on `.ok`, do
   not rely on raised errors.
5. **Nothing else needs wiring.** Requiring the module is the entire setup:
   persistence, player lifecycle, replication, and the wallet UI all start
   automatically.

---

## 2. Installation

Vendor the library (e.g. as a submodule at `packages/economy`):

```bash
mkdir -p packages
git submodule add https://github.com/RBClauneck/economy.git packages/economy
```

Map the single module into your host project's `default.project.json`,
anywhere under `ReplicatedStorage` so both sides can require it:

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

Require it from any server or client script:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyProvider = require(ReplicatedStorage:WaitForChild("EconomyProvider"))
```

There is no separate server, client, or shared folder to map — the same
module works on both sides.

---

## 3. Server API

Available when `EconomyProvider` is required from server-side code.

### `EconomyProvider.addMoney(userId, currency, amount) → MutationResult`

Adds `amount` of `currency` to the player. Validated against overflow and the
currency ceiling. Safe for any trusted server caller.

| Param | Type | Description |
| :--- | :--- | :--- |
| `userId` | `number` | Target player's `UserId`. |
| `currency` | `CurrencyId` (`string`) | Registered currency id, e.g. `"gold"`. |
| `amount` | `number` | Non-negative integer to add. |

```lua
local result = EconomyProvider.addMoney(player.UserId, "gold", 50)
if result.ok then
    print("New gold balance:", result.balance)
else
    warn("Add failed:", result.reason)
end
```

### `EconomyProvider.minusMoney(userId, currency, amount) → MutationResult`

Removes `amount` of `currency`. **Fails without mutating** when the player
lacks sufficient funds (`reason = "insufficient funds"`). Same params as
`addMoney`.

```lua
local result = EconomyProvider.minusMoney(player.UserId, "coin", 10)
if not result.ok then
    warn(result.reason) -- e.g. "insufficient funds", "no active session for player"
end
```

### `EconomyProvider.getBalance(userId, currency) → number?`

Reads a single balance. Returns `nil` if the player has no active session or
the currency is unknown.

```lua
local gold = EconomyProvider.getBalance(player.UserId, "gold") or 0
```

### `EconomyProvider.getWallet(userId) → Wallet?`

Returns the player's whole wallet (`{ [CurrencyId]: number }`), or `nil` if
they have no active session.

```lua
local wallet = EconomyProvider.getWallet(player.UserId)
if wallet then
    for currency, balance in wallet do
        print(currency, balance)
    end
end
```

### `EconomyProvider.canAfford(userId, currency, amount) → boolean`

Convenience guard for purchase flows: `true` only when the player can afford
`amount`. **Not atomic** — still rely on `minusMoney`'s result as the source of
truth (it re-checks atomically).

```lua
if EconomyProvider.canAfford(player.UserId, "gold", price) then
    local result = EconomyProvider.minusMoney(player.UserId, "gold", price)
    if result.ok then grantItem() end
end
```

> **A balance only exists while the player has an active session.** All read/
> mutate calls return `nil`/`{ ok = false, reason = "no active session..." }`
> before the profile loads or after the player leaves. Session lifecycle
> (loading, backfilling new currencies, saving, releasing) is wired
> automatically into `Players.PlayerAdded` / `PlayerRemoving` — you never call
> it yourself.

---

## 4. Currency registry (server and client)

### `EconomyProvider.registerCurrency(options) → CurrencyDefinition`

Registers a **custom currency**. Must be called **at boot, before any profile
loads**, on **both** the server and the client (the client needs it to label
UI). Returns the frozen definition. Asserts (raises) on invalid input.

`options`:

| Field | Type | Required | Default | Rules |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `string` | ✅ | — | Non-empty, **lowercase**, not already registered. |
| `displayName` | `string` | — | `id` | Human-readable label. |
| `default` | `number` | — | `0` | `>= 0`. Starting balance for new profiles. |
| `max` | `number` | — | `MAX_SAFE_AMOUNT` (`2^53 - 1`) | `>= default`. Hard mutation ceiling. |

```lua
-- Immediately after requiring the module, before any player joins:
EconomyProvider.registerCurrency({ id = "gem", displayName = "Gem", max = 1_000_000 })
```

### Base currencies (always present, no registration)

| id | displayName | default | max |
| :--- | :--- | :--- | :--- |
| `coin` | Coin | `0` | `MAX_SAFE_AMOUNT` |
| `copper` | Copper | `0` | `MAX_SAFE_AMOUNT` |
| `silver` | Silver | `0` | `MAX_SAFE_AMOUNT` |
| `gold` | Gold | `0` | `MAX_SAFE_AMOUNT` |

### `EconomyProvider.getCurrencyDefinition(id) → CurrencyDefinition?`

Returns the definition for a currency, or `nil` if not registered.

### `EconomyProvider.getAllCurrencies() → { CurrencyDefinition }`

Returns the shared, **insertion-ordered** list of every registered definition
(base currencies first, then customs in registration order). The returned array
and its definitions are frozen — iterate, never mutate.

```lua
for _, def in EconomyProvider.getAllCurrencies() do
    print(def.displayName, def.default, def.max)
end
```

---

## 5. Client API (read-only)

Available when `EconomyProvider` is required from client-side code. Contains
no mutation or networking calls of its own — it only reflects server-decided
state.

### `EconomyProvider.getLocalBalance(currency) → number`

Last synced balance for a currency, or its configured `default` if nothing has
synced yet. Always returns a number (never `nil`).

```lua
local gold = EconomyProvider.getLocalBalance("gold")
```

### `EconomyProvider.onBalanceChanged(listener) → unsubscribe`

Subscribes to balance changes. `listener` is called as
`listener(currency: CurrencyId, balance: number)` on every change (each
listener runs in its own `task.spawn`). Returns an unsubscribe function.

```lua
local disconnect = EconomyProvider.onBalanceChanged(function(currency, balance)
    print(currency, "is now", balance)
end)
-- later:
disconnect()
```

### `EconomyProvider.mountWalletGui() → ScreenGui?`

Mounts the built-in read-only currency panel (search, sort, live updates) and
returns its `ScreenGui`. Called automatically once when the module loads on
the client — you only need this if you destroyed the original panel and want
a fresh one.

---

## 6. Replication

Server→Client wallet sync rides a single `RemoteEvent` the module creates for
itself as a child of the `EconomyProvider` ModuleScript instance.

- The **server is the only side that calls `FireClient`.**
- The client fires the event **with no arguments** to request a fresh
  snapshot on load; the server answers from authoritative state and ignores
  any data the client sends.
- This is entirely internal — consumers never touch the RemoteEvent directly;
  use the functions in [§3](#3-server-api) and [§5](#5-client-api-read-only)
  instead.

---

## 7. Types

```lua
-- Canonical lowercase key addressing a currency everywhere.
export type CurrencyId = string

-- Immutable description of a currency, registered once at boot.
export type CurrencyDefinition = {
    id: CurrencyId,        -- canonical key, e.g. "gold"
    displayName: string,   -- human label, e.g. "Gold"
    default: number,       -- starting balance for a fresh profile
    max: number,           -- hard ceiling enforced on every mutation
    isBase: boolean,       -- true for the four built-in base currencies
}

-- Options accepted by registerCurrency.
export type CustomCurrencyOptions = {
    id: CurrencyId,
    displayName: string?,
    default: number?,
    max: number?,
}

-- Player balances: every known CurrencyId → non-negative integer.
export type Wallet = { [CurrencyId]: number }

-- Returned by every mutating call. Branch on `ok`; do not rely on errors.
export type MutationResult = {
    ok: boolean,
    balance: number?,  -- new balance when ok == true
    reason: string?,   -- failure reason when ok == false
}
```

### `MutationResult.reason` values

| `reason` | Cause |
| :--- | :--- |
| `"must be called from the server"` | A server-only function was called from the client. |
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

## 8. Persistence (internal)

The server side of `EconomyProvider` owns an in-house, **session-locked**
DataStore wrapper. You never call it directly; it is wired into player
lifecycle automatically. Key guarantees:

- **Session locking:** a profile can only be edited by one server at a time.
  A lock is "live" while `os.time() - heartbeat < 600`; the auto-save loop
  refreshes the heartbeat every `60` seconds so a running server keeps
  ownership and a crashed server's lock goes stale and is reclaimed. Prevents
  two servers corrupting one profile.
- **Auto-save:** every active profile is persisted every `60` seconds.
- **`BindToClose` durability:** all profiles are final-saved and unlocked
  before shutdown, so no in-flight balance change is lost on a restart.
- **Reconcile:** loaded profiles gain newly-added fields (e.g. a newly
  registered currency) without wiping existing data.

If a session lock cannot be acquired (another live server still holds it),
the player is kicked with:
*"Your economy data is busy on another server. Please rejoin in a moment."*

---

## 9. Quick reference

| I want to... | Use | Side |
| :--- | :--- | :--- |
| Give a player currency | `EconomyProvider.addMoney(userId, id, amount)` | Server |
| Charge a player | `EconomyProvider.minusMoney(userId, id, amount)` | Server |
| Check a server-side balance | `EconomyProvider.getBalance(userId, id)` | Server |
| Get a player's full wallet | `EconomyProvider.getWallet(userId)` | Server |
| Pre-check affordability | `EconomyProvider.canAfford(userId, id, amount)` | Server |
| Add a new currency type | `EconomyProvider.registerCurrency({ id = ... })` (at boot) | Both |
| List all currencies | `EconomyProvider.getAllCurrencies()` | Both |
| Look up a currency's definition | `EconomyProvider.getCurrencyDefinition(id)` | Both |
| Read a balance for UI | `EconomyProvider.getLocalBalance(id)` | Client |
| React to balance changes | `EconomyProvider.onBalanceChanged(fn)` | Client |
| Remount the built-in wallet panel | `EconomyProvider.mountWalletGui()` | Client |
