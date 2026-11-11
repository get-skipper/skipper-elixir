defmodule Skipper do
  @moduledoc """
  Runtime shared by the framework adapters (`skipper_ex_unit`, `skipper_espec`):
  load the spreadsheet once per run, answer "should this test run?", collect
  discovered test IDs, then emit the report and sync at the end.
  """

  alias Skipper.{Config, Log, Report, Resolver, Writer}

  @key {__MODULE__, :state}
  @registry Skipper.Registry

  @doc """
  Load the spreadsheet. Options:

    * `:config` — a `Skipper.Config` (default: `Skipper.Config.from_env/0`)
    * `:resolver` — use this `Skipper.Resolver` instead of fetching

  Without a config every test runs. Raises only when the sheet cannot be loaded
  and `SKIPPER_FAIL_OPEN=false`.
  """
  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    config = Keyword.get_lazy(opts, :config, &Config.from_env/0)

    resolver =
      cond do
        r = opts[:resolver] ->
          r

        config ->
          case Resolver.initialize(config) do
            {:ok, r} -> r
            {:error, reason} -> raise "[skipper] cannot load spreadsheet: #{reason}"
          end

        true ->
          Log.log("SKIPPER_SPREADSHEET_ID / credentials not set — Skipper disabled")
          nil
      end

    :persistent_term.put(@key, %{config: config, resolver: resolver})

    case Agent.start(fn -> %{discovered: [], suppressed: []} end, name: @registry) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        Agent.update(@registry, fn _ -> %{discovered: [], suppressed: []} end)
    end

    :ok
  end

  @doc "The loaded resolver, or nil when Skipper is not started/configured."
  def resolver, do: :persistent_term.get(@key, %{resolver: nil}).resolver

  @doc "Replace the resolver (e.g. to add fixture entries in tests)."
  def put_resolver(resolver) do
    state = :persistent_term.get(@key, %{config: nil, resolver: nil})
    :persistent_term.put(@key, %{state | resolver: resolver})
  end

  @doc """
  Record `test_id` as discovered and tell whether it should run:
  `:run` or `{:skip, message}`.
  """
  @spec check(String.t()) :: :run | {:skip, String.t()}
  def check(test_id) do
    case resolver() do
      nil ->
        :run

      r ->
        enabled = Resolver.enabled?(r, test_id)

        Agent.update(@registry, fn s ->
          %{
            s
            | discovered: [test_id | s.discovered],
              suppressed: if(enabled, do: s.suppressed, else: [test_id | s.suppressed])
          }
        end)

        if enabled, do: :run, else: {:skip, Resolver.skip_message(r, test_id)}
    end
  end

  @doc "True with `SKIPPER_MODE=sync`."
  def sync_mode?, do: System.get_env("SKIPPER_MODE") == "sync"

  @doc """
  Emit the quarantine report and, in sync mode, reconcile the sheet. Returns
  `{:error, reason}` (already printed) when the sync fails.
  """
  @spec finish() :: :ok | {:error, String.t()}
  def finish do
    # Runs once per start/1: umbrella apps share a VM and re-fire after_suite hooks.
    state = :persistent_term.get(@key, %{config: nil, resolver: nil})
    :persistent_term.put(@key, %{config: nil, resolver: nil})

    with r when not is_nil(r) <- state.resolver do
      %{discovered: d, suppressed: s} = Agent.get(@registry, & &1)
      discovered = d |> Enum.reverse() |> Enum.uniq()
      suppressed = Enum.reverse(s)
      now = DateTime.utc_now()

      re_enabled =
        Enum.filter(discovered, fn id ->
          until = Resolver.disabled_until(r, id)
          id not in suppressed and until != nil and DateTime.compare(until, now) != :gt
        end)

      Report.emit(Report.build(r.cache, suppressed, re_enabled))
      config = state.config

      if sync_mode?() and config do
        case Writer.sync(config, discovered) do
          :ok ->
            IO.puts(:stderr, "[skipper] synced #{length(discovered)} test IDs")

          {:error, reason} ->
            IO.puts(:stderr, "[skipper] sync failed: #{reason}")
            {:error, reason}
        end
      else
        :ok
      end
    else
      _ -> :ok
    end
  end
end
