defmodule Skipper.IntegrationTest do
  # Talks to the real shared spreadsheet. Skipped without credentials:
  # set GOOGLE_CREDS_B64 or put service-account-skipper-bot.json at the repo root.
  use ExUnit.Case

  @spreadsheet_id "1Nbjfhklw11uVbi6OCOSeCJI_PThJYzQLlZQbThb4Zvs"
  @key_file Path.expand("../../../service-account-skipper-bot.json", __DIR__)

  creds =
    cond do
      (b64 = System.get_env("GOOGLE_CREDS_B64")) not in [nil, ""] -> {:base64, b64}
      File.exists?(@key_file) -> {:file, @key_file}
      true -> nil
    end

  @creds creds
  if is_nil(creds), do: @moduletag(skip: "no Google credentials")

  defp config do
    id =
      System.get_env("SKIPPER_SPREADSHEET_ID")
      |> then(&if(&1 in [nil, ""], do: @spreadsheet_id, else: &1))

    %Skipper.Config{spreadsheet_id: id, credentials: @creds, sheet_name: "skipper-elixir"}
  end

  test "fetches the real sheet" do
    {:ok, api} = Skipper.SheetsApi.HTTP.new(config().credentials)
    {:ok, %{primary: p}} = Skipper.Client.fetch_all(api, config())
    assert p.sheet_name == "skipper-elixir"
    assert "testId" in p.header
    assert p.sheet_id != 0
  end

  test "resolver initializes without fallbacks" do
    System.put_env("SKIPPER_FAIL_OPEN", "false")
    System.put_env("SKIPPER_CACHE_TTL", "0")

    try do
      assert {:ok, r} = Skipper.Resolver.initialize(config())
      assert Skipper.Resolver.enabled?(r, "not/in/sheet.exs > anything")
    after
      System.delete_env("SKIPPER_FAIL_OPEN")
      System.delete_env("SKIPPER_CACHE_TTL")
    end
  end
end
