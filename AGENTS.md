# RBClauneck Economy Library - AI Agents

This repository contains the core economy library for RBClauneck. All AI agents working on this project must strictly adhere to the rules defined in this document and the architectural guidelines in [SKILLS.md](SKILLS.md). Context-specific rules live in the `.agents/` directory — load them on demand via the index below.

# Agent Instructions

**Strict Rules:**
- Agents must ask for the user's approval before editing `AGENTS.md` or `SKILLS.md`.
- Never work directly on the `master` or `main` branch.
- Always verify if your current task aligns with the active branch. If it does not, create a new branch. Do not create a new branch if you are continuing existing work on the appropriate branch.

The root `AGENTS.md` and `SKILLS.md` files must remain universally applicable to the entire repository. If you conceptualize a new instruction or skill that is specific to a certain context and not universal, create it within the `.agents/` or `.skills/` directories instead.

**Directory Structure:**
- `.agents/{type}/{name}.md`
- `.skills/{type}/{name}.md`

**Indexing Rules:**
- All indexes must be written within this `AGENTS.md` file.
- All references and indexing for files within the `.agents/` and `.skills/` directories MUST be written as bullet points directly within this `AGENTS.md` file.
- Do not use or create central index files (such as `README.md`) inside the `.agents/` or `.skills/` directories.

**Examples of Direct Indexing:**
- IF working with credentials: READ `.agents/rules/credential.md`
- IF working with Git rules: READ `.agents/git/rules.md`
- IF managing pull requests: READ `.agents/git/workflows.md`
- IF modifying database structures: READ `.skills/db/structure.md`
- IF implementing caching: READ `.skills/workflows/caching.md`
- IF updating data models: READ `.skills/models/structure.md`

## Suggesting New Content

While working, if you discover a useful idea, rule, or skill that could improve `AGENTS.md` or `SKILLS.md`, do not apply the changes immediately. Instead, upon finishing your current task, suggest the new additions to the user and allow them to decide whether to integrate them.

## Modular Instruction Index

This file stays universally applicable. Context-specific rules live under `.agents/`
(and skills under `.skills/`); load only the file(s) your task needs.

* **Git — commit conventions:** [`.agents/git/commits.md`](.agents/git/commits.md)
* **Git — branching & PR workflow:** [`.agents/git/workflows.md`](.agents/git/workflows.md)

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
