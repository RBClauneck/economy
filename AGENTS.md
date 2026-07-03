# RBClauneck Economy Library - AI Agents

This repository contains the core internal **economy** library for RBClauneck: a
secure, exploit-proof, server-authoritative currency system shared across every
RBClauneck place. Trusted server modules (Market, Trading, Rewards) mutate balances
through a single entry point (`EconomyProvider`); the client is strictly read-only
and never computes a balance. All AI agents working on this project MUST strictly
adhere to the rules defined in this document.

## Strict Rules

- Agents must ask for the user's approval before editing `AGENTS.md`.
- Never work directly on the `master` or `main` branch.
- Always verify that your current task aligns with the active branch. If it does
  not, create a new branch. Do not create a new branch when you are continuing
  existing work on the appropriate branch.

This root `AGENTS.md` must remain universally applicable to the entire repository.
If you conceptualize an instruction that is specific to a certain context and not
universally applicable, place it under `.agents/{type}/{name}.md` instead of
bloating this file.

## Git & Commit Conventions

- **Branch Naming (STRICT):** Must follow `{type}/{primary-noun}` or
  `{type}/{primary-noun}-{secondary-noun}` (e.g. `feat/wallet`,
  `fix/overflow-guard`). Do not use verbs, Jira ids, or a `claude/` prefix.
  Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
  `build`, `ci`, `chore`, `revert`.
- **Commits:** Follow the Conventional Commits specification. Keep messages plain:
  no links, no session links, and do not reference pull requests or issues with `#`.
  Always review the diff before committing.
- **Pull Requests:** Ask the user for permission before opening a PR.

## Repository Map

The full, file-by-file map of this repository lives in [INDEX.md](INDEX.md). Keep it
accurate: whenever files or directories are added, removed, or restructured, update
`INDEX.md` in the same change.

## Coding Standards & Code Generation

When instructed to create, modify, or refactor code, agents MUST follow these
principles:

- **Strict Luau Typing:** Every `.luau` file MUST begin with `--!strict`. Explicitly
  declare types for variables, function parameters, return values, and exported
  module tables.
- **Single Entry Point:** `EconomyProvider` (`src/server/EconomyProvider.luau`) is
  the ONLY module trusted server callers require. Consumers must never reach into
  `CurrencyService`, `ProfileStore`, `Replication`, or `Validation` directly —
  extend the facade rather than bypassing it.
- **Structural Placement (Client-Server separation):** Before writing any code,
  verify its correct location:
  - `src/server/` — authoritative logic: `EconomyProvider` (the facade),
    `CurrencyService` (core `addMoney`/`minusMoney`/`getBalance` mutations), the
    session-locked `ProfileStore` (in-house DataStore wrapper), `Replication`
    (server→client wallet sync over `WalletSyncEvent`), `Validation`, and the
    bootstrap `init.server.luau`.
  - `src/client/` — read-only wallet display: `WalletController` (mirrors the synced
    wallet, exposes `getBalance`/`onChanged`) and `WalletGui`. It never computes or
    persists a balance.
  - `src/shared/` — the server/client contract: `Types`, `Constants` (DataStore and
    RemoteEvent names, timings), and `CurrencyConfig` (the currency registry). No
    authoritative logic or secrets live here; it replicates to clients.
- **Server-Authoritative Mutations:** All balance changes happen on the server via
  `EconomyProvider.addMoney` / `EconomyProvider.minusMoney`. The client submits
  nothing that mutates money; it only observes the wallet replicated over
  `WalletSyncEvent`.
- **Read-Only Client (ZERO TRUST):** Never trust the client. It exists solely to
  observe state and update the GUI: it never calculates a balance, holds
  authoritative state, or writes to the DataStore. Everything it displays arrives
  from the server and is treated as strictly read-only.
- **Currency Registry:** The four base currencies (`coin`, `copper`, `silver`,
  `gold`) plus any custom currencies are defined in `src/shared/CurrencyConfig.luau`
  — the single source of truth read by both server and client. Register custom
  currencies via `CurrencyConfig.register` before profiles load.
- **Input & Result Validation:** Validate every mutation through `Validation` before
  it touches a wallet. Reject NaN, infinity, negatives, non-integers, overflow, and
  any amount that would breach the per-currency ceiling.
- **Persistence:** Route all DataStore access through the session-locked
  `ProfileStore` with auto-save, `BindToClose` durability, and bounded
  exponential-backoff retries. Do not scatter raw `DataStoreService` calls across
  scripts.
- **Modularity:** Avoid monolithic scripts. Break complex logic into smaller,
  single-responsibility `ModuleScript` files.
- **Non-Blocking Critical Paths:** Do not yield (e.g. `task.wait()`) inside a
  mutation or a tight loop unless explicitly wrapping a Roblox DataStore or
  HttpService asynchronous call.

## Suggesting New Content

While working, if you discover a useful idea, rule, or skill that could improve
`AGENTS.md`, do not apply the change immediately. Instead, upon finishing your
current task, suggest the addition to the user and allow them to decide whether to
integrate it.
