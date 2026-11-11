defmodule Skipper.Resolver do
  @moduledoc """
  Decides whether a test runs. Tests not in the spreadsheet always run
  (opt-out model); a test with a future `disabledUntil` is skipped.
  """

  alias Skipper.{Client, Log, TestId}

  @default_cache_file ".skipper-cache.json"
  @default_ttl 300

  @type t :: %__MODULE__{cache: %{String.t() => DateTime.t() | nil}}
  defstruct cache: %{}

  @doc "Fetch the spreadsheet once. See `initialize_with/1` for the fallback rules."
  @spec initialize(Skipper.Config.t()) :: {:ok, t()} | {:error, String.t()}
  def initialize(config) do
    initialize_with(fn ->
      with {:ok, api} <- Skipper.SheetsApi.HTTP.new(config.credentials),
           {:ok, %{entries: entries}} <- Client.fetch_all(api, config) do
        {:ok, entries}
      end
    end)
  end

  @doc """
  Build the resolver from `fetch` (returns `{:ok, entries}`). If it fails: use
  the disk cache (`SKIPPER_CACHE_FILE`, default `.skipper-cache.json`) when
  younger than `SKIPPER_CACHE_TTL` seconds (default 300, `0` disables it);
  else, with `SKIPPER_FAIL_OPEN` (default true), run every test; else error.
  """
  @spec initialize_with((-> {:ok, [Client.entry()]} | {:error, String.t()})) ::
          {:ok, t()} | {:error, String.t()}
  def initialize_with(fetch) do
    Log.log("initializing resolver")
    cache_file = env("SKIPPER_CACHE_FILE") || @default_cache_file

    ttl =
      case Integer.parse(env("SKIPPER_CACHE_TTL") || "") do
        {n, ""} when n >= 0 -> n
        _ -> @default_ttl
      end

    fail_open =
      String.downcase(String.trim(System.get_env("SKIPPER_FAIL_OPEN", "true"))) != "false"

    result =
      try do
        fetch.()
      rescue
        e -> {:error, Exception.message(e)}
      end

    case result do
      {:ok, entries} ->
        cache = Map.new(entries, &{TestId.normalize(&1.test_id), &1.disabled_until})
        Log.log("loaded #{map_size(cache)} test entries from spreadsheet")
        if ttl > 0, do: write_disk_cache(cache_file, cache)
        {:ok, %__MODULE__{cache: cache}}

      {:error, reason} ->
        cached = if ttl > 0, do: read_disk_cache(cache_file, ttl)

        cond do
          cached ->
            {age, cache} = cached
            Log.warn("API failed (#{reason}), using cache (#{round(age)}s old)")
            {:ok, %__MODULE__{cache: cache}}

          fail_open ->
            Log.warn("API failed (#{reason}), no valid cache — running all tests (fail-open)")
            {:ok, %__MODULE__{}}

          true ->
            {:error, reason}
        end
    end
  end

  @spec enabled?(t(), String.t()) :: boolean()
  def enabled?(%__MODULE__{cache: cache}, test_id) do
    case Map.get(cache, TestId.normalize(test_id)) do
      nil -> true
      until -> DateTime.compare(DateTime.utc_now(), until) != :lt
    end
  end

  @doc "Instant the test is re-enabled (midnight UTC after the sheet date), or nil."
  def disabled_until(%__MODULE__{cache: cache}, test_id),
    do: Map.get(cache, TestId.normalize(test_id))

  @doc "`[skipper] Test disabled until <sheet date>`."
  def skip_message(resolver, test_id) do
    case disabled_until(resolver, test_id) do
      nil -> "[skipper] Test disabled"
      until -> "[skipper] Test disabled until #{Date.add(DateTime.to_date(until), -1)}"
    end
  end

  @doc "Add or override entries (test ID → re-enable instant). Handy in tests."
  def put(%__MODULE__{cache: cache} = r, entries) do
    %{r | cache: Enum.into(entries, cache, fn {k, v} -> {TestId.normalize(k), v} end)}
  end

  defp env(name) do
    case System.get_env(name) do
      v when v in [nil, ""] -> nil
      v -> v
    end
  end

  defp write_disk_cache(path, cache) do
    entries = Map.new(cache, fn {k, v} -> {k, v && DateTime.to_iso8601(v)} end)
    payload = Jason.encode!(%{ts: System.os_time(:millisecond) / 1000, entries: entries})

    case File.write(path, payload) do
      :ok ->
        :ok

      {:error, reason} ->
        Log.warn("could not write API cache to #{path}: #{:file.format_error(reason)}")
    end
  end

  defp read_disk_cache(path, ttl) do
    with {:ok, data} <- File.read(path),
         {:ok, %{"ts" => ts, "entries" => entries}} when is_number(ts) and is_map(entries) <-
           Jason.decode(data),
         age = System.os_time(:millisecond) / 1000 - ts,
         true <- age <= ttl do
      {age, Map.new(entries, fn {k, v} -> {k, parse_dt(v)} end)}
    else
      _ -> nil
    end
  end

  defp parse_dt(nil), do: nil

  defp parse_dt(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
