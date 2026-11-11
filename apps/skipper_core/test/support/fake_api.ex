defmodule Skipper.FakeApi do
  @moduledoc false
  @behaviour Skipper.SheetsApi
  # client: an Agent pid holding %{sheets: [{title, id, values}], appended: [], batches: []}

  def new(sheets) do
    {:ok, pid} = Agent.start_link(fn -> %{sheets: sheets, appended: [], batches: []} end)
    {__MODULE__, pid}
  end

  def state({_, pid}), do: Agent.get(pid, & &1)

  @impl true
  def get_spreadsheet(pid, _id) do
    sheets = Agent.get(pid, & &1.sheets)

    {:ok,
     %{
       "sheets" =>
         for({t, id, _} <- sheets, do: %{"properties" => %{"title" => t, "sheetId" => id}})
     }}
  end

  @impl true
  def get_values(pid, _id, range) do
    case Enum.find(Agent.get(pid, & &1.sheets), fn {t, _, _} -> t == range end) do
      {_, _, values} -> {:ok, %{"values" => values}}
      nil -> {:error, "no sheet #{range}"}
    end
  end

  @impl true
  def append_values(pid, _id, _range, rows),
    do: {:ok, Agent.update(pid, &%{&1 | appended: &1.appended ++ rows})}

  @impl true
  def batch_update(pid, _id, requests),
    do: {:ok, Agent.update(pid, &%{&1 | batches: &1.batches ++ requests})}
end
