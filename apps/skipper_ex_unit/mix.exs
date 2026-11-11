defmodule Skipper.ExUnit.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source "https://github.com/get-skipper/skipper-elixir"

  def project do
    [
      app: :skipper_ex_unit,
      version: @version,
      elixir: "~> 1.17",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps(),
      description:
        "Skipper for ExUnit (and Wallaby/Hound): enable or disable tests from a Google Spreadsheet.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source, "Website" => "https://get-skipper.github.io"},
        files: ~w(lib mix.exs README.md LICENSE)
      ],
      docs: [main: "readme", extras: ["README.md"], source_url: @source]
    ]
  end

  def application, do: [extra_applications: [:logger, :ex_unit]]

  defp deps do
    [
      # Hex packages can't depend on umbrella siblings: publish with HEX_PUBLISH=1.
      if(System.get_env("HEX_PUBLISH"),
        do: {:skipper_core, "~> #{@version}"},
        else: {:skipper_core, in_umbrella: true}
      ),
      {:wallaby, "~> 0.30", only: :test, runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
