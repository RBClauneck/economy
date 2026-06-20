# RBClauneck Economy Library

Welcome to the **RBClauneck Economy Library**. This project serves as the core internal economy API designed to be shared across all places within the RBClauneck organization. 

It is built with a secure, exploit-proof architecture, utilizing modern state synchronization to ensure flawless data consistency between the Roblox Server and Client.

## 🌟 Key Features

* **Internal Core API:** Acts as the central backend service for other server-side modules (e.g., Market, Trading) to safely mutate economy states.
* **Modern State Sync & Persistence:** Strictly utilizes **DataKeep** for safe DataStore session locking and **ReplicaService** for robust one-way (Server-to-Client) state synchronization.
* **Read-Only Client Separation:** Strict boundaries where the client side is designed to be purely read-only, existing solely to observe state changes and update the GUI.
* **Rojo Integration:** Fully configured with a `default.project.json` to automatically route modules to their correct Roblox DataModel locations (`ServerScriptService`, `StarterPlayerScripts`, and `ReplicatedStorage`).
* **AI-Assisted Workflow:** Pre-configured with `AGENTS.md`, `SKILLS.md`, and `CLAUDE.md` to enforce strict coding standards, Git workflows, and architectural rules for AI agents like Claude Code.

## 📁 Project Structure

The repository is organized to support a modular and secure workflow:

* **`src/server/`** — Contains backend logic, DataKeep implementations, and the core internal API exposed to other server modules.
* **`src/client/`** — Contains frontend logic exclusively for reading replicated data (via ReplicaService) and triggering UI updates.
* **`src/shared/`** — Contains shared resources acting as a bridge between the server and client, such as Constants, Types, Configs, and Replica definitions.
* **`aftman.toml`** — Manages cross-platform toolchains to ensure consistent versions of tools like Rojo (`rojo-rbx/rojo@7.7.0-rc.1`) across the entire team and CI/CD pipelines.

## 🤖 AI Agent Instructions

If you are an AI assistant (e.g., Claude Code), you MUST adhere to the following rules:
1. You must read [AGENTS.md](AGENTS.md) and [SKILLS.md](SKILLS.md) before executing any task.
2. Ensure all data mutations happen on the server using **DataKeep**, and sync state to the client exclusively via **ReplicaService**. Treat the client state as strictly read-only.
3. All commits must strictly follow the Conventional Commits specification outlined in `AGENTS.md`.

## 🚀 Installation (For Place Repositories)

To integrate this library into your main place repository, add it as a Git submodule:

```bash
mkdir -p packages
git submodule add https://github.com/RBClauneck/economy.git packages/economy
