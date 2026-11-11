defmodule Skipper.Core.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source "https://github.com/get-skipper/skipper-elixir"

  def project do
    [
      app: :skipper_core,
      version: @version,
      elixir: "~> 1.17",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: deps(),
      description:
        "Core of Skipper: test-gating via Google Spreadsheet (resolver, Sheets client, sync writer).",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source, "Website" => "https://get-skipper.github.io"},
        files: ~w(lib mix.exs README.md LICENSE)
      ],
      docs: [main: "readme", extras: ["README.md"], source_url: @source]
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl, :public_key, :crypto]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
