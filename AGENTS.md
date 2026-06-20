# RBClauneck Economy Library - AI Agents

This repository contains the core economy library for RBClauneck. All AI agents working on this project must strictly adhere to the rules defined in this document and the architectural guidelines in [SKILLS.md](SKILLS.md).

## Commit Message Conventions (STRICT)

Commits MUST follow the Conventional Commits specification. Commit messages must be plain and contain no links; do not reference pull requests or issues with #.

**Structure**
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]

**Types**
* `fix:` — Patches a bug (PATCH).
* `feat:` — Introduces a new feature (MINOR).
* `BREAKING CHANGE:` — Introduces a breaking API change (MAJOR).
* Other supported types: `build:`, `chore:`, `ci:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`

**Examples**
* `feat(api)!: send an email to the customer when a product is shipped`
* `fix: prevent racing of requests`
* `chore(rojo): initial project structure`

## Git & Branching Workflow

* **Branch Isolation (CRITICAL):** NEVER work directly in the master branch. If the current branch is master, checkout a new branch immediately before making modifications.
* **Task Scoping:** When you start work from a user prompt, check whether it relates to the current branch. If the task is unrelated, create a new branch specific to it. If the work stays within the current scope — for example, adding a new function or fixing an error in existing work — do not create a new branch; continue on the current one.
* **Branch Naming (STRICT):** Must strictly follow the `{type}/{primary-noun}` or `{type}/{primary-noun}-{secondary-noun}` format. Do not use verbs or Jira IDs.
  * Allowed Types: `feat/`, `fix/`, `docs/`, `style/`, `refactor/`, `perf/`, `test/`, `build/`, `ci/`, `chore/`, `revert/`
* **Commit Frequency & Verification:** Commit each change or group related commits. Do not wait for the entire session to finish. Always check the diff before creating a commit.
* **Pull Requests (PR):** PRs must be opened sequentially in the correct order. Always ask the user for permission before creating a PR.
* **Branch Check Before Working:** Before starting any work, always check the current branch. You must never work directly in the master or main branch.

## Coding Standards & Code Generation

When instructed to create, modify, or refactor code, agents MUST follow these principles:

* **Strict Luau Typing:** All Luau files (`.luau`) MUST begin with `--!strict`. You must explicitly declare types for variables, function parameters, return values, and exported module tables.
* **Structural Placement:** Before writing any code, verify its correct location based on the Client-Server separation model:
  * `src/server/` for backend logic, DataStores, and providing the core economy API to other server modules.
  * `src/client/` for UI updates and reading replicated economy data.
  * `src/shared/` for shared Constants, Types, Configs, and RemoteEvents.
* **Data Management & State Sync:** You MUST use the **Custom In-House Session-Locked DataStore Wrapper** (`ProfileStore` in `src/server`) for all Roblox DataStore operations; it provides session locking, auto-save, and `BindToClose` safety with strict typing. Do NOT reintroduce third-party persistence or replication libraries. To synchronize state from the server to the client, you MUST use **Standard Roblox RemoteEvents** (the `WalletSyncEvent`). The client must treat all received data as strictly read-only.
* **Internal API Validation:** As a core library, this module does not process client inputs directly. However, its server-side functions (e.g., `addMoney`, `minusMoney`) MUST rigorously validate all arguments passed by other server modules. Always check for invalid numbers (e.g., block negative values, `NaN`, floating-point errors, or integer overflows) before executing any economy mutation to prevent cascading errors from other systems.
* **Read-Only Client:** The client side of this library exists solely to observe state changes (received over the `WalletSyncEvent` RemoteEvent) and update the GUI. It must not contain logic to request economy mutations.
* **Modularity:** Avoid monolithic scripts. Break complex logic into smaller, single-responsibility `ModuleScript` files.
* **Non-Blocking Critical Paths:** Do not yield (e.g., `task.wait()`) inside transactional logic or critical loops unless explicitly wrapping a Roblox DataStore asynchronous call.
