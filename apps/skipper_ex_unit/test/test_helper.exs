# Real spreadsheet (skipper-elixir tab) when SKIPPER_SPREADSHEET_ID + credentials
# are set — that's how CI dogfoods sync. Otherwise Skipper starts unconfigured.
Skipper.ExUnit.start()

# Fixture entries prove the skip path: these tests flunk if they ever run.
until = ~U[2099-01-02 00:00:00Z]

Skipper.put_resolver(
  Skipper.Resolver.put(Skipper.resolver() || %Skipper.Resolver{}, %{
    "apps/skipper_ex_unit/test/gating_test.exs > top level disabled" => until,
    "apps/skipper_ex_unit/test/gating_test.exs > a group > disabled in describe" => until,
    "apps/skipper_ex_unit/test/wallaby_test.exs > disabled feature" => until
  })
)

ExUnit.start()
