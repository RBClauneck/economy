# Repository Index

This file maps the contents of this repository. Keep it accurate: whenever
files or directories are added, removed, or restructured, update the entries
below.

## Root Files

| Path | Purpose |
|---|---|
| README.md | Overview, key features, currency system, and installation guide. |
| AGENTS.md | Primary AI-agent instruction set: strict rules, Git conventions, and economy-specific coding standards. |
| INDEX.md | This file: the repository map. |
| default.project.json | Rojo project file mapping `src/{shared,server,client}` into the Roblox DataModel. |
| aftman.toml | Pinned toolchain versions (Rojo) for local and CI builds. |
| .gitignore | Files and directories excluded from version control. |

## src/server/ — Server-Authoritative Economy Core

| Path | Purpose |
|---|---|
| src/server/EconomyProvider.luau | The single entry point: a thin facade over `CurrencyService` and `CurrencyConfig` that trusted server modules (Market, Trading, Rewards) require. |
| src/server/init.server.luau | Bootstrap: wires player lifecycle into persistence and replication. |
| src/server/CurrencyService.luau | Internal core mutation logic (`addMoney`, `minusMoney`, `getBalance`, `getWallet`, `canAfford`); not required directly by consumers. |
| src/server/ProfileStore.luau | In-house session-locked DataStore wrapper. |
| src/server/Replication.luau | Server to client wallet sync over `WalletSyncEvent`. |
| src/server/Validation.luau | Argument and result validation for economy mutations. |

## src/client/ — Read-Only Client (Zero Trust)

The client never calculates a balance; it only displays what the server has
already decided. See `platforms/ROBLOX.md` in the shared `.agents` repository
for the general client zero-trust guidance this follows.

| Path | Purpose |
|---|---|
| src/client/init.client.luau | Bootstrap: feeds the controller from `WalletSyncEvent`. |
| src/client/WalletController.luau | Read-only wallet mirror with `getBalance` / `onChanged`. |
| src/client/WalletGui.luau | Built-in currency panel UI. |

## src/shared/ — Server/Client Contract

| Path | Purpose |
|---|---|
| src/shared/Types.luau | Shared type definitions (`Wallet`, `MutationResult`, etc.). |
| src/shared/Constants.luau | Centralised constants (DataStore name, RemoteEvent name, timings). |
| src/shared/CurrencyConfig.luau | Currency registry: base currencies plus `register` for custom ones. |

## wiki/ — Reference Documentation

| Path | Purpose |
|---|---|
| wiki/API.md | Self-contained API reference for consumers vendoring this library. |

## .github/workflows/ — CI

| Path | Purpose |
|---|---|
| .github/workflows/notify-master.yml | Notifies dependent repos on push to master. |
| .github/workflows/sync-test-branch.yml | Keeps a test branch in sync. |
