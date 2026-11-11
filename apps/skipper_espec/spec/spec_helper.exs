# Real spreadsheet (skipper-elixir tab) when configured via env; fixture
# entries below prove the skip path (those examples fail if they ever run).
Skipper.ESpec.start()

until = ~U[2099-01-02 00:00:00Z]

Skipper.put_resolver(
  Skipper.Resolver.put(Skipper.resolver() || %Skipper.Resolver{}, %{
    "apps/skipper_espec/spec/gating_spec.exs > disabled example" => until,
    "apps/skipper_espec/spec/gating_spec.exs > a context > nested > disabled nested example" =>
      until
  })
)
