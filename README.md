# RBClauneck Economy Library

Welcome to the **RBClauneck Economy Library**. This project serves as the core economy system designed to be shared across all places within the RBClauneck organization. 

It is built with a secure, exploit-proof architecture, ensuring flawless synchronization between the Roblox Server and Client.

## 🌟 Key Features

* **Client-Server Separation:** Strict boundaries between backend logic and frontend UI to ensure the client is never trusted with critical economy mutations.
* **Rojo Integration:** Fully configured with a `default.project.json` to automatically route modules to their correct Roblox DataModel locations (`ServerScriptService`, `StarterPlayerScripts`, and `ReplicatedStorage`).
* **AI-Assisted Workflow:** Pre-configured with `AGENTS.md`, `SKILLS.md`, and `CLAUDE.md` to enforce strict coding standards, Git workflows, and architectural rules for AI agents like Claude Code.

## 📁 Project Structure

The repository is organized to support a modular and secure workflow:

* **`src/server/`** — Contains backend logic, secure DataStore operations, and transaction validations.
* **`src/client/`** — Contains frontend logic, UI updates, and visual effect handlers.
* **`src/shared/`** — Contains shared resources acting as a bridge between the server and client, such as Constants, Types, Configs, and RemoteEvents.
* **`aftman.toml`** — Manages cross-platform toolchains to ensure consistent versions of tools like Rojo (`rojo-rbx/rojo@7.7.0-rc.1`) across the entire team and CI/CD pipelines.

## 🤖 AI Agent Instructions

If you are an AI assistant (e.g., Claude Code), you MUST adhere to the following rules:
1. You must read [AGENTS.md](AGENTS.md) and [SKILLS.md](SKILLS.md) before executing any task.
2. Never trust the client; route all Roblox DataStore reads and writes through a dedicated service manager in `src/server/`.
3. All commits must strictly follow the Conventional Commits specification outlined in `AGENTS.md`.

## 🚀 Installation (For Place Repositories)

To integrate this library into your main place repository, add it as a Git submodule:

```bash
mkdir -p packages
git submodule add https://github.com/RBClauneck/economy.git packages/economy
```
