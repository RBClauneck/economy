# Commit Message Conventions (STRICT)

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
