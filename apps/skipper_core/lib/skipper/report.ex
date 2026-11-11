defmodule Skipper.Report do
  @moduledoc "Quarantine-debt summary emitted at the end of a run."

  @doc """
  `entries`: resolver cache; `suppressed`: IDs skipped in this run;
  `re_enabled`: IDs that ran although listed with an already expired date.
  """
  def build(entries, suppressed, re_enabled) do
    now = DateTime.utc_now()
    week = DateTime.add(now, 7 * 86_400, :second)
    active = for {_, d} <- entries, d != nil, DateTime.compare(d, now) == :gt, do: d

    %{
      generated_at: DateTime.to_iso8601(now),
      currently_suppressed: length(active),
      suppressed_this_run: suppressed |> Enum.uniq() |> Enum.sort(),
      expiring_this_week: Enum.count(active, &(DateTime.compare(&1, week) != :gt)),
      re_enabled_this_run: re_enabled |> Enum.uniq() |> Enum.sort(),
      quarantine_days_debt:
        active |> Enum.map(&max(div(DateTime.diff(&1, now), 86_400), 0)) |> Enum.sum()
    }
  end

  def markdown(r) do
    table = """
    ## Skipper Quarantine Report

    | Metric | Value |
    |--------|-------|
    | Currently suppressed | #{r.currently_suppressed} |
    | Suppressed this run | #{length(r.suppressed_this_run)} |
    | Expiring this week | #{r.expiring_this_week} |
    | Re-enabled this run | #{length(r.re_enabled_this_run)} |
    | Quarantine-days debt | #{r.quarantine_days_debt} |

    """

    lists =
      for {title, ids} <- [
            {"Suppressed this run", r.suppressed_this_run},
            {"Re-enabled this run", r.re_enabled_this_run}
          ],
          ids != [],
          into: "" do
        "### #{title}\n\n" <> Enum.map_join(ids, "", &"- `#{&1}`\n") <> "\n"
      end

    table <> lists
  end

  @doc """
  Append the markdown to `$GITHUB_STEP_SUMMARY` (else print it) and write
  `skipper-report.json` in the current directory.
  """
  def emit(report) do
    md = markdown(report)

    case System.get_env("GITHUB_STEP_SUMMARY") do
      path when path not in [nil, ""] -> File.write!(path, md, [:append])
      _ -> IO.puts(md)
    end

    File.write!("skipper-report.json", Jason.encode!(report, pretty: true))
  end
end
