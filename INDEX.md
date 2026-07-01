# Repository Index

This file maps the contents of this repository. Keep it accurate: whenever
files or directories are added, removed, or restructured, update the entries
below.

## Root Files

| Path | Purpose |
|---|---|
| README.md | Overview, key features, currency system, and installation guide. |
| default.project.json | Rojo project file mapping `src/EconomyProvider.luau` into `ReplicatedStorage`. |
| aftman.toml | Pinned toolchain versions (Rojo) for local and CI builds. |
| .gitignore | Files and directories excluded from version control. |

## src/ — The Library

| Path | Purpose |
|---|---|
| src/EconomyProvider.luau | The entire economy package in one drop-in ModuleScript: currency registry, validation, session-locked persistence, replication, the server mutation API, the client wallet mirror, and the built-in wallet UI. Detects server vs. client automatically. |

## wiki/ — Reference Documentation

| Path | Purpose |
|---|---|
| wiki/API.md | Self-contained API reference for consumers vendoring this library. |

## .github/workflows/ — CI

| Path | Purpose |
|---|---|
| .github/workflows/notify-master.yml | Notifies dependent repos on push to master. |
| .github/workflows/sync-test-branch.yml | Keeps a test branch in sync. |
