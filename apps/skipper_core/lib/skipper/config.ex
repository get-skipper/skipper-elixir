defmodule Skipper.Config do
  @moduledoc """
  Skipper configuration.

  `credentials` is one of:

    * `{:file, path}` — service-account JSON key file
    * `{:base64, encoded}` — base64-encoded service-account JSON (CI secrets)
    * `{:service_account, map}` — inline service-account fields (string or atom keys)
  """

  @type credentials ::
          {:file, Path.t()} | {:base64, String.t()} | {:service_account, map()}

  @type t :: %__MODULE__{
          spreadsheet_id: String.t(),
          credentials: credentials(),
          sheet_name: String.t() | nil,
          reference_sheets: [String.t()],
          test_id_column: String.t(),
          disabled_until_column: String.t()
        }

  # Never print key material.
  @derive {Inspect, except: [:credentials]}
  @enforce_keys [:spreadsheet_id, :credentials]
  defstruct [
    :spreadsheet_id,
    :credentials,
    sheet_name: nil,
    reference_sheets: [],
    test_id_column: "testId",
    disabled_until_column: "disabledUntil"
  ]

  @doc """
  Build a config from the environment: `SKIPPER_SPREADSHEET_ID`, credentials
  from `SKIPPER_CREDENTIALS_FILE` (wins) or `GOOGLE_CREDS_B64`, optional
  `SKIPPER_SHEET_NAME` and comma-separated `SKIPPER_REFERENCE_SHEETS`.
  Returns `nil` when Skipper is not configured.
  """
  @spec from_env() :: t() | nil
  def from_env do
    with id when is_binary(id) <- env("SKIPPER_SPREADSHEET_ID"),
         creds when not is_nil(creds) <- env_credentials() do
      %__MODULE__{
        spreadsheet_id: id,
        credentials: creds,
        sheet_name: env("SKIPPER_SHEET_NAME"),
        reference_sheets:
          (env("SKIPPER_REFERENCE_SHEETS") || "")
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      }
    else
      _ -> nil
    end
  end

  defp env_credentials do
    cond do
      file = env("SKIPPER_CREDENTIALS_FILE") -> {:file, file}
      b64 = env("GOOGLE_CREDS_B64") -> {:base64, b64}
      true -> nil
    end
  end

  defp env(name) do
    case System.get_env(name) do
      nil -> nil
      v -> if String.trim(v) == "", do: nil, else: v
    end
  end

  @doc "Resolve the credentials to a service-account map (string keys)."
  @spec service_account(credentials()) :: {:ok, map()} | {:error, String.t()}
  def service_account({:file, path}) do
    case File.read(path) do
      {:ok, json} ->
        decode(json)

      {:error, reason} ->
        {:error, "cannot read credentials file #{path}: #{:file.format_error(reason)}"}
    end
  end

  def service_account({:base64, enc}) do
    case Base.decode64(String.trim(enc)) do
      {:ok, json} -> decode(json)
      :error -> {:error, "credentials are not valid base64"}
    end
  end

  def service_account({:service_account, map}) when is_map(map),
    do: {:ok, Map.new(map, fn {k, v} -> {to_string(k), v} end)}

  def service_account(other), do: {:error, "unsupported credentials: #{inspect(elem_tag(other))}"}

  defp elem_tag(t) when is_tuple(t), do: elem(t, 0)
  defp elem_tag(t), do: t

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, "credentials are not a JSON object"}
    end
  end
end
