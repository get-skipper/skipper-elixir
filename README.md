# skipper-elixir

[![CI](https://github.com/get-skipper/skipper-elixir/actions/workflows/ci.yml/badge.svg)](https://github.com/get-skipper/skipper-elixir/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/skipper_ex_unit.svg)](https://hex.pm/packages/skipper_ex_unit)
[![License](https://img.shields.io/github/license/get-skipper/skipper-elixir)](LICENSE)

Test-gating for Elixir via Google Spreadsheet. Enable or disable tests without changing code — just update a date in a Google Sheet.

An Elixir port of [get-skipper/skipper](https://github.com/get-skipper/skipper), supporting ExUnit (including [Wallaby](https://github.com/elixir-wallaby/wallaby) and [Hound](https://github.com/HashNuke/hound) browser tests) and [ESpec](https://github.com/antonmi/espec).

---

## How it works

A Google Spreadsheet stores test IDs with optional `disabledUntil` dates:

| testId | disabledUntil | notes |
|--------|---------------|-------|
| `test/auth_test.exs > can log in` | | |
| `test/payment_test.exs > checkout > with valid card` | `2099-12-31` | Flaky on CI |
| `spec/auth_spec.exs > login > rejects bad passwords` | `2026-06-01` | Under investigation |

- **Empty `disabledUntil`** → test runs normally
- **Past date** → test runs normally
- **Future date** → test is skipped (it stays disabled through the whole `disabledUntil` day, UTC)

Tests not listed in the spreadsheet **always run** (opt-out model).

---

## Packages

| Package | Framework |
|---------|-----------|
| [`skipper_ex_unit`](https://hex.pm/packages/skipper_ex_unit) | ExUnit, Wallaby, Hound |
| [`skipper_espec`](https://hex.pm/packages/skipper_espec) | ESpec |
| [`skipper_core`](https://hex.pm/packages/skipper_core) | Shared core (resolver, Sheets client, writer, report) |

Requires Elixir 1.17+ / OTP 27+. The core only depends on `jason`: HTTP and JWT signing use OTP's `:httpc` and `:public_key`.

---

## Installation

```elixir
# mix.exs
defp deps do
  [
    {:skipper_ex_unit, "~> 1.0", only: :test},
    # or
    {:skipper_espec, "~> 1.0", only: :test}
  ]
end
```

---

## Google Sheets setup

1. Create a Google Spreadsheet with the following columns in row 1:
   - `testId`
   - `disabledUntil`
   - `notes` (optional)

2. Create a Google Cloud service account and download the JSON key file.

3. Share the spreadsheet with the service account's email (`client_email` in the JSON).

4. Note the spreadsheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/YOUR_SPREADSHEET_ID/edit`

---

## Credentials

| Format | Value | Use case |
|--------|-------|----------|
| File path | `{:file, "./service-account.json"}` | Local development |
| Base64 string | `{:base64, System.get_env("GOOGLE_CREDS_B64")}` | CI/CD env vars |
| Inline map | `{:service_account, %{"client_email" => ..., "private_key" => ...}}` | Programmatic use |

Without an explicit config, Skipper reads the environment: `SKIPPER_SPREADSHEET_ID`, then
`SKIPPER_CREDENTIALS_FILE` or `GOOGLE_CREDS_B64`, and optionally `SKIPPER_SHEET_NAME`. With
neither, Skipper is disabled and every test runs.

---

## Usage

### ExUnit

```elixir
# test/test_helper.exs
Skipper.ExUnit.start(
  config: %Skipper.Config{
    spreadsheet_id: "your-spreadsheet-id",
    credentials: {:file, "./service-account.json"},
    sheet_name: "my-app"
  }
)

ExUnit.start()
```

```elixir
defmodule MyApp.AuthTest do
  use Skipper.Case              # must come BEFORE use ExUnit.Case
  use ExUnit.Case, async: true

  test "can log in" do
    # ...
  end

  describe "checkout" do
    test "with valid card" do
      # ...
    end
  end
end
```

`use Skipper.Case` must precede `use ExUnit.Case` — or the case template that calls it,
such as `use MyAppWeb.ConnCase` (Skipper raises a clear error otherwise). Disabled tests are
reported as **skipped** with the reason `[skipper] Test disabled until 2099-12-31`; a test that
already has a `@tag :skip` keeps its own reason.

**Test ID format:** `test/auth_test.exs > can log in`, `test/payment_test.exs > checkout > with valid card`

### Wallaby and Hound

Wallaby features and Hound tests are ExUnit tests, so `Skipper.Case` gates them the same way.
A disabled feature never starts a browser session.

```elixir
defmodule MyAppWeb.LoginFeatureTest do
  use Skipper.Case
  use ExUnit.Case, async: true
  use Wallaby.Feature

  feature "user logs in", %{session: session} do
    # ...
  end
end
```

**Test ID format:** `test/features/login_feature_test.exs > user logs in`

### ESpec

```elixir
# spec/spec_helper.exs
Skipper.ESpec.start(config: %Skipper.Config{spreadsheet_id: "...", credentials: {:file, "./service-account.json"}})
```

```elixir
defmodule AuthSpec do
  use Skipper.ESpec             # must come BEFORE use ESpec
  use ESpec

  describe "login" do
    it "rejects bad passwords" do
      # ...
    end
  end
end
```

Disabled examples are reported as **pending** with the Skipper reason.

**Test ID format:** `spec/auth_spec.exs > login > rejects bad passwords`

---

## Modes

| Mode | Env var | Behavior |
|------|---------|----------|
| `read-only` (default) | — | Fetch spreadsheet, skip disabled tests |
| `sync` | `SKIPPER_MODE=sync` | Same as above, then reconcile spreadsheet with discovered tests |

In sync mode, every test **defined** in the compiled test files is added to the spreadsheet
(including ones excluded by tags); existing rows are never modified. Deletion of orphaned rows
requires `SKIPPER_SYNC_ALLOW_DELETE=true`. A failing sync makes the run exit non-zero.
Run sync without `--partitions`.

At the end of every run Skipper writes a quarantine report to `skipper-report.json` and to
`$GITHUB_STEP_SUMMARY` (or stdout).

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SKIPPER_SPREADSHEET_ID` | — | Spreadsheet to read (when no `:config` is given) |
| `SKIPPER_CREDENTIALS_FILE` | — | Service-account JSON file (wins over `GOOGLE_CREDS_B64`) |
| `GOOGLE_CREDS_B64` | — | Base64-encoded service-account JSON |
| `SKIPPER_SHEET_NAME` | first sheet | Primary sheet name |
| `SKIPPER_REFERENCE_SHEETS` | — | Comma-separated read-only sheets to merge in |
| `SKIPPER_MODE` | `read-only` | Set to `sync` to enable sync mode |
| `SKIPPER_DEBUG` | — | Any non-empty value enables verbose debug logging |
| `SKIPPER_FAIL_OPEN` | `true` | When the API is unreachable and no fresh disk cache exists, run all tests. Set to `false` to fail instead |
| `SKIPPER_CACHE_TTL` | `300` | Seconds the on-disk cache stays valid as an API fallback. `0` disables it |
| `SKIPPER_CACHE_FILE` | `.skipper-cache.json` | Location of the on-disk cache |
| `SKIPPER_SYNC_ALLOW_DELETE` | `false` | In sync mode, also delete rows of tests that no longer exist |

---

## Test ID matching

- Paths are relative to the project root (the umbrella root in an umbrella project), using `/`
- Title parts are separated by ` > `; the `test`/`feature` prefix ExUnit adds to names is dropped
- IDs are case-insensitive and whitespace-collapsed for matching

---

## Reference sheets

Inherit disabled tests from additional read-only sheets:

```elixir
%Skipper.Config{
  spreadsheet_id: "your-spreadsheet-id",
  credentials: {:file, "./service-account.json"},
  reference_sheets: ["GlobalDisabled", "FlakyTests"]
}
```

When the same test ID appears in multiple sheets, the most restrictive (latest) `disabledUntil` date wins.

---

## CI example

```yaml
- name: Run tests
  run: mix test
  env:
    SKIPPER_SPREADSHEET_ID: ${{ secrets.SKIPPER_SPREADSHEET_ID }}
    GOOGLE_CREDS_B64: ${{ secrets.GOOGLE_CREDS_B64 }}
```

---

## License

[MIT](LICENSE)
