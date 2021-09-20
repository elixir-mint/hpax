defmodule HPAX.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/elixir-mint/hpax"

  def project do
    [
      app: :hpax,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      package: package(),
      description: "Small and composable HTTP client.",

      # Docs
      name: "HPAX",
      docs: [
        source_ref: "v#{@version}",
        source_url: @repo_url
      ]
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp deps do
    []
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @repo_url}
    ]
  end
end
