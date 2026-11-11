# Contributing to skipper-elixir

Thank you for your interest in contributing!

---

## Requirements

- Elixir 1.17+ / OTP 27+
- A Google Cloud service account (for integration testing against a real spreadsheet)

## Setup

```bash
git clone https://github.com/get-skipper/skipper-elixir.git
cd skipper-elixir
mix deps.get
```

Put `service-account-skipper-bot.json` at the repository root (gitignored) or set
`GOOGLE_CREDS_B64` to run the integration tests; without it they are skipped.

## Running tests

```bash
make test
```

## Linting

```bash
make lint
```

Linting must pass before a pull request can be merged.

---

## Commit messages

All commits **must** follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
type(scope): short description

[optional body]

[optional footer]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | A new feature or integration |
| `fix` | A bug fix |
| `docs` | Documentation changes only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Build process, dependency updates, tooling |

### Scopes

| Scope | Applies to |
|-------|------------|
| `core` | `apps/skipper_core` |
| `ex_unit` | `apps/skipper_ex_unit` |
| `espec` | `apps/skipper_espec` |

### Examples

```
feat(ex_unit): gate doctests
fix(core): keep the sheet row index when blank rows are present
docs(espec): document nested contexts in test IDs
test(core): cover reference-sheet merge collisions
chore: bump jason
```

---

## Changelog

All notable changes are recorded in [CHANGELOG.md](CHANGELOG.md) following the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

- Entries live under `## [Unreleased]` until a release is cut.
- Every change belongs to one of: `Added`, `Changed`, `Deprecated`, `Removed`,
  `Fixed`, `Security`.
- When a new version is released, rename `## [Unreleased]` to
  `## [x.y.z] – YYYY-MM-DD`, add a fresh empty `## [Unreleased]` section at
  the top, and append a comparison link at the bottom of the file.

---

## Pull requests

1. Fork the repository and create a branch:
   ```bash
   git checkout -b feat/my-feature
   ```

2. Make your changes. Ensure:
   - `make test` passes
   - `make lint` passes
   - New functionality has corresponding unit tests

3. Commit using Conventional Commits format (see above).

4. Open a pull request with a clear title and description.

---

## Project structure

```
apps/skipper_core/     # Config, Sheets client (JWT via :public_key, :httpc), resolver, writer, report, Skipper runtime
apps/skipper_ex_unit/  # Skipper.ExUnit (suite hooks) and Skipper.Case (compile-time gating)
apps/skipper_espec/    # Skipper.ESpec (spec_helper hook and compile-time gating)
```

Each framework integration should:
- Call `Skipper.start/1` once before the test files are compiled
- Gate each test with `Skipper.check/1` (it also records the ID for sync) using the framework's native skip
- Call `Skipper.finish/0` once after the run (report, and sync in sync mode)

See existing integrations for reference patterns.
