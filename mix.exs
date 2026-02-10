defmodule Reproject.Mixfile do
  use Mix.Project

  def project do
    [
      app: :reproject,
      version: "1.0.0",
      elixir: ">= 1.17.0",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      package: package(),
      description: description(),
      deps: deps()
    ]
  end

  defp description do
    """
      NIFs for repojecting points with proj4. Inspiration from greenelephantlabs/proj4erl.
    """
  end

  defp package do
    [
      maintainers: ["Chris Duranti"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/rozap/reproject"},
      files: ~w"""
        mix.exs
        README.md
        LICENSE
        Makefile
        config
        src
        lib
      """
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.9.0", runtime: false}
    ]
  end
end
