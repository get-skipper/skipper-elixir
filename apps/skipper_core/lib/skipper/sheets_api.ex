defmodule Skipper.SheetsApi do
  @moduledoc """
  The four Google Sheets v4 calls Skipper needs. An API handle is
  `{module, client}`; `Skipper.SheetsApi.HTTP` is the real implementation and
  tests can pass an in-memory fake.
  """

  @type api :: {module(), term()}
  @type result(t) :: {:ok, t} | {:error, String.t()}

  @callback get_spreadsheet(client :: term(), spreadsheet_id :: String.t()) :: result(map())
  @callback get_values(client :: term(), spreadsheet_id :: String.t(), range :: String.t()) ::
              result(map())
  @callback append_values(term(), String.t(), String.t(), rows :: [[String.t()]]) ::
              result(term())
  @callback batch_update(term(), String.t(), requests :: [map()]) :: result(term())

  def get_spreadsheet({mod, c}, id), do: mod.get_spreadsheet(c, id)
  def get_values({mod, c}, id, range), do: mod.get_values(c, id, range)
  def append_values({mod, c}, id, range, rows), do: mod.append_values(c, id, range, rows)
  def batch_update({mod, c}, id, requests), do: mod.batch_update(c, id, requests)
end

defmodule Skipper.SheetsApi.HTTP do
  @moduledoc """
  Sheets API over HTTPS (`:httpc`), authenticated with a service-account JWT
  (OAuth 2.0 `jwt-bearer` grant, RS256 signed with `:public_key`).
  """
  @behaviour Skipper.SheetsApi

  @scope "https://www.googleapis.com/auth/spreadsheets"
  @default_token_uri "https://oauth2.googleapis.com/token"
  @base "https://sheets.googleapis.com/v4/spreadsheets"
  @timeout 30_000

  @doc "Authenticate and return an API handle `{__MODULE__, client}`."
  @spec new(Skipper.Config.credentials()) :: {:ok, Skipper.SheetsApi.api()} | {:error, String.t()}
  def new(credentials) do
    with {:ok, sa} <- Skipper.Config.service_account(credentials),
         {:ok, token} <- access_token(sa) do
      {:ok, {__MODULE__, %{token: token}}}
    end
  end

  @impl true
  def get_spreadsheet(%{token: t}, id), do: request(:get, "#{@base}/#{enc(id)}", t)

  @impl true
  def get_values(%{token: t}, id, range),
    do: request(:get, "#{@base}/#{enc(id)}/values/#{enc(range)}", t)

  @impl true
  def append_values(%{token: t}, id, range, rows) do
    url = "#{@base}/#{enc(id)}/values/#{enc(range)}:append?valueInputOption=RAW"
    request(:post, url, t, %{values: rows})
  end

  @impl true
  def batch_update(%{token: t}, id, requests),
    do: request(:post, "#{@base}/#{enc(id)}:batchUpdate", t, %{requests: requests})

  defp access_token(sa) do
    email = sa["client_email"]
    pem = sa["private_key"]

    if blank?(email) or blank?(pem) do
      {:error, "credentials missing client_email or private_key"}
    else
      token_uri = if blank?(sa["token_uri"]), do: @default_token_uri, else: sa["token_uri"]
      now = System.os_time(:second)
      header = %{"alg" => "RS256", "typ" => "JWT"}

      header =
        if blank?(sa["private_key_id"]),
          do: header,
          else: Map.put(header, "kid", sa["private_key_id"])

      claims = %{
        "iss" => email,
        "scope" => @scope,
        "aud" => token_uri,
        "iat" => now,
        "exp" => now + 3600
      }

      with {:ok, jwt} <- sign(header, claims, pem),
           body =
             URI.encode_query(%{
               "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion" => jwt
             }),
           {:ok, %{"access_token" => token}} <-
             http(:post, token_uri, [], {~c"application/x-www-form-urlencoded", body}) do
        {:ok, token}
      else
        {:ok, other} -> {:error, "token response without access_token: #{inspect(other)}"}
        err -> err
      end
    end
  end

  defp sign(header, claims, pem) do
    input = b64(Jason.encode!(header)) <> "." <> b64(Jason.encode!(claims))

    try do
      [entry | _] = :public_key.pem_decode(pem)
      key = :public_key.pem_entry_decode(entry)
      {:ok, input <> "." <> b64(:public_key.sign(input, :sha256, key))}
    rescue
      e -> {:error, "invalid private_key: #{Exception.message(e)}"}
    end
  end

  defp request(method, url, token, json \\ nil) do
    headers = [{~c"authorization", String.to_charlist("Bearer " <> token)}]
    body = if json, do: {~c"application/json", Jason.encode!(json)}, else: nil
    http(method, url, headers, body)
  end

  defp http(method, url, headers, body) do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    req =
      case body do
        nil -> {String.to_charlist(url), headers}
        {type, data} -> {String.to_charlist(url), headers, type, data}
      end

    case :httpc.request(method, req, [ssl: ssl, timeout: @timeout, connect_timeout: @timeout],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _, resp}} when status in 200..299 ->
        case Jason.decode(resp) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "invalid JSON from #{url}"}
        end

      {:ok, {{_, status, _}, _, resp}} ->
        {:error, "HTTP #{status} from #{url}: #{resp}"}

      {:error, reason} ->
        {:error, "request to #{url} failed: #{inspect(reason)}"}
    end
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)
  defp enc(s), do: URI.encode(s, &URI.char_unreserved?/1)
  defp blank?(v), do: v in [nil, ""]
end
