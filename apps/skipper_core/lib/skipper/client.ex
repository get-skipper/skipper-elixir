defmodule Skipper.Client do
  @moduledoc "Reads the spreadsheet: primary sheet plus reference sheets, merged."

  alias Skipper.{Log, SheetsApi, TestId}

  @type entry :: %{
          test_id: String.t(),
          disabled_until: DateTime.t() | nil,
          notes: String.t(),
          row: non_neg_integer()
        }
  @type sheet :: %{
          sheet_name: String.t(),
          sheet_id: integer(),
          header: [String.t()],
          entries: [entry()]
        }

  @doc """
  Fetch the primary sheet and merge every reference sheet into it (latest date
  wins). A failing reference sheet is skipped with a warning.
  """
  @spec fetch_all(SheetsApi.api(), Skipper.Config.t()) ::
          {:ok, %{primary: sheet(), entries: [entry()]}} | {:error, String.t()}
  def fetch_all(api, config) do
    with {:ok, meta} <- SheetsApi.get_spreadsheet(api, config.spreadsheet_id),
         name = primary_name(config, meta),
         {:ok, primary} <- fetch_sheet(api, config, meta, name) do
      merged =
        Enum.reduce(config.reference_sheets, merge([], primary.entries), fn ref, acc ->
          case fetch_sheet(api, config, meta, ref) do
            {:ok, sheet} ->
              merge(acc, sheet.entries)

            {:error, reason} ->
              Log.warn("cannot fetch reference sheet #{inspect(ref)}: #{reason}")
              acc
          end
        end)

      {:ok, %{primary: primary, entries: merged}}
    end
  end

  defp primary_name(%{sheet_name: name}, _meta) when is_binary(name) and name != "", do: name

  defp primary_name(_config, meta),
    do: get_in(meta, ["sheets", Access.at(0), "properties", "title"]) || ""

  defp fetch_sheet(api, config, meta, name) do
    with {:ok, resp} <- SheetsApi.get_values(api, config.spreadsheet_id, name) do
      sheet_id = sheet_id(meta, name)

      case Map.get(resp, "values", []) do
        [] ->
          {:ok, %{sheet_name: name, sheet_id: sheet_id, header: [], entries: []}}

        [header | rows] ->
          header = Enum.map(header, &(&1 |> cell() |> String.trim()))
          parse_rows(config, name, sheet_id, header, rows)
      end
    end
  end

  defp parse_rows(config, name, sheet_id, header, rows) do
    idx = fn col -> Enum.find_index(header, &(&1 == col)) end

    case idx.(config.test_id_column) do
      nil ->
        {:error, "column #{inspect(config.test_id_column)} not found in sheet #{inspect(name)}"}

      id_idx ->
        until_idx = idx.(config.disabled_until_column)
        notes_idx = idx.("notes")

        rows
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {row, i}, {:ok, acc} ->
          row = Enum.map(row, &cell/1)
          test_id = row |> Enum.at(id_idx, "") |> String.trim()

          cond do
            test_id == "" ->
              {:cont, {:ok, acc}}

            true ->
              raw = if until_idx, do: Enum.at(row, until_idx, ""), else: ""

              case parse_disabled_until(raw, i + 1) do
                {:ok, until} ->
                  notes = if notes_idx, do: Enum.at(row, notes_idx, ""), else: ""
                  entry = %{test_id: test_id, disabled_until: until, notes: notes, row: i}
                  {:cont, {:ok, [entry | acc]}}

                error ->
                  {:halt, error}
              end
          end
        end)
        |> case do
          {:ok, entries} ->
            entries = Enum.reverse(entries)
            Log.log("fetched #{length(entries)} entries from sheet #{inspect(name)}")
            {:ok, %{sheet_name: name, sheet_id: sheet_id, header: header, entries: entries}}

          error ->
            error
        end
    end
  end

  defp cell(v) when is_binary(v), do: v
  defp cell(nil), do: ""
  defp cell(v), do: to_string(v)

  defp sheet_id(meta, name) do
    meta
    |> Map.get("sheets", [])
    |> Enum.find_value(0, fn s ->
      s["properties"]["title"] == name && s["properties"]["sheetId"]
    end)
  end

  @doc """
  Parse a `disabledUntil` cell. Only strict `YYYY-MM-DD` is accepted; the
  result is midnight UTC of the *following* day, so the test stays disabled for
  the whole calendar day. Empty means no date. `row` (1-based sheet row,
  0 = unknown) only appears in the error message.
  """
  @spec parse_disabled_until(String.t(), non_neg_integer()) ::
          {:ok, DateTime.t() | nil} | {:error, String.t()}
  def parse_disabled_until(raw, row \\ 0) do
    s = String.trim(raw)

    cond do
      s == "" ->
        {:ok, nil}

      s =~ ~r/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/ and match?({:ok, _}, Date.from_iso8601(s)) ->
        {:ok, date} = Date.from_iso8601(s)
        {:ok, DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")}

      true ->
        loc = if row > 0, do: "row #{row}: ", else: ""
        {:error, "[skipper] #{loc}invalid disabledUntil #{inspect(s)}. Use YYYY-MM-DD."}
    end
  end

  @doc false
  # Merge by normalized ID; on collision the later date wins, a date beats nil.
  def merge(existing, incoming) do
    keyed = fn list -> Enum.map(list, &{TestId.normalize(&1.test_id), &1}) end

    {order, by_id} =
      Enum.reduce(keyed.(existing) ++ keyed.(incoming), {[], %{}}, fn {nid, e}, {order, by_id} ->
        case by_id do
          %{^nid => cur} ->
            if later?(e.disabled_until, cur.disabled_until),
              do: {order, Map.put(by_id, nid, %{cur | disabled_until: e.disabled_until})},
              else: {order, by_id}

          _ ->
            {[nid | order], Map.put(by_id, nid, e)}
        end
      end)

    order |> Enum.reverse() |> Enum.map(&Map.fetch!(by_id, &1))
  end

  defp later?(nil, _), do: false
  defp later?(_, nil), do: true
  defp later?(a, b), do: DateTime.compare(a, b) == :gt
end
