# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] – 2026-11-11

### Added

- `skipper_core`: resolver (opt-out model, strict `YYYY-MM-DD` dates expiring at
  midnight UTC after the given day), Google Sheets client with service-account
  JWT auth on OTP's `:public_key`/`:httpc`, reference-sheet merge (latest date
  wins), sync writer, disk cache fallback (`SKIPPER_CACHE_TTL`), fail-open
  (`SKIPPER_FAIL_OPEN`) and quarantine report (`skipper-report.json`,
  `GITHUB_STEP_SUMMARY`).
- `skipper_ex_unit`: `Skipper.ExUnit.start/1` and `use Skipper.Case` — disabled
  tests are reported as skipped; covers Wallaby features and Hound tests.
- `skipper_espec`: `Skipper.ESpec.start/1` and `use Skipper.ESpec` — disabled
  examples are reported as pending.

[Unreleased]: https://github.com/get-skipper/skipper-elixir/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/get-skipper/skipper-elixir/releases/tag/v1.0.0
