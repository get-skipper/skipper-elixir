defmodule Skipper.Writer do
  @moduledoc """
  Reconciles the primary sheet with the test IDs discovered in a run: new IDs
  are appended (empty `disabledUntil`); stale rows of the same files are
  deleted only with `SKIPPER_SYNC_ALLOW_DELETE=true`. Existing rows are never
  modified.
  """

  alias Skipper.{Client, Log, SheetsApi, TestId}

  @spec sync(Skipper.Config.t(), [String.t()]) :: :ok | {:error, String.t()}
  def sync(config, discovered) do
    with {:ok, api} <- SheetsApi.HTTP.new(config.credentials) do
      sync_with(api, config, discovered)
    end
  end

  @spec sync_with(SheetsApi.api(), Skipper.Config.t(), [String.t()]) :: :ok | {:error, String.t()}
  def sync_with(api, config, discovered) do
    Log.log("syncing #{length(discovered)} discovered test IDs")

    with {:ok, %{primary: primary}} <- Client.fetch_all(api, config),
         {:ok, id_idx} <- id_index(primary, config),
         :ok <- delete_stale(api, config, primary, discovered) do
      append_new(api, config, primary, id_idx, discovered)
    end
  end

  defp id_index(primary, config) do
    case Enum.find_index(primary.header, &(&1 == config.test_id_column)) do
      nil ->
        {:error,
         "column #{inspect(config.test_id_column)} not found in sheet #{inspect(primary.sheet_name)}"}

      i ->
        {:ok, i}
    end
  end

  defp delete_stale(api, config, primary, discovered) do
    discovered_set = MapSet.new(discovered, &TestId.normalize/1)

    owned_files =
      for nid <- discovered_set,
          [file, _] <- [String.split(nid, " > ", parts: 2)],
          into: MapSet.new(),
          do: file

    owned_bases = MapSet.new(owned_files, &Path.basename/1)

    rows =
      for e <- primary.entries,
          nid = TestId.normalize(e.test_id),
          stale?(nid, owned_files, owned_bases, discovered_set),
          do: e.row

    allow? =
      String.downcase(String.trim(System.get_env("SKIPPER_SYNC_ALLOW_DELETE", ""))) == "true"

    cond do
      rows == [] ->
        :ok

      not allow? ->
        Log.warn(
          "#{length(rows)} orphaned row(s) found but not deleted. " <>
            "Set SKIPPER_SYNC_ALLOW_DELETE=true to prune them."
        )

        :ok

      true ->
        requests =
          for r <- Enum.sort(rows, :desc) do
            %{
              deleteDimension: %{
                range: %{
                  sheetId: primary.sheet_id,
                  dimension: "ROWS",
                  startIndex: r,
                  endIndex: r + 1
                }
              }
            }
          end

        with {:ok, _} <- SheetsApi.batch_update(api, config.spreadsheet_id, requests) do
          Log.log("deleted #{length(rows)} rows from spreadsheet")
          :ok
        end
    end
  end

  # Malformed rows (no " > ") are always stale; others only within owned files.
  defp stale?(nid, owned_files, owned_bases, discovered_set) do
    case String.split(nid, " > ", parts: 2) do
      [_] ->
        true

      [file, _] ->
        owned =
          MapSet.member?(owned_files, file) or
            (not String.contains?(file, "/") and MapSet.member?(owned_bases, file))

        owned and not MapSet.member?(discovered_set, nid)
    end
  end

  defp append_new(api, config, primary, id_idx, discovered) do
    existing = MapSet.new(primary.entries, &TestId.normalize(&1.test_id))

    {rows, _} =
      Enum.reduce(discovered, {[], existing}, fn id, {rows, seen} ->
        nid = TestId.normalize(id)

        if MapSet.member?(seen, nid) do
          {rows, seen}
        else
          row = List.replace_at(List.duplicate("", length(primary.header)), id_idx, id)
          {[row | rows], MapSet.put(seen, nid)}
        end
      end)

    case Enum.reverse(rows) do
      [] ->
        :ok

      rows ->
        with {:ok, _} <-
               SheetsApi.append_values(api, config.spreadsheet_id, primary.sheet_name, rows) do
          Log.log("appended #{length(rows)} new test IDs to spreadsheet")
          :ok
        end
    end
  end
end
