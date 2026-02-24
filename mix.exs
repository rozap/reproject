defmodule Reproject.Mixfile do
  use Mix.Project

  @version "1.0.0-rc.0"

  @precompiler_opts (if System.get_env("REPROJECT_BUILD_FROM_SOURCE") do
                       []
                     else
                       [
                         make_precompiler: {:nif, CCPrecompiler},
                         make_precompiler_url:
                           "https://github.com/Tango-Tango/reproject/releases/download/v#{@version}/@{artefact_filename}",
                         make_precompiler_filename: "reproject",
                         make_precompiler_priv_paths: ["reproject.*", "proj_data"],
                         make_precompiler_nif_versions: [
                           versions: ["2.16", "2.17"],
                           fallback_version: "2.17"
                         ]
                       ]
                     end)

  def project do
    [
      app: :reproject,
      version: @version,
      elixir: ">= 1.17.0",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      package: package(),
      description: description(),
      deps: deps()
    ] ++ @precompiler_opts
  end

  defp description do
    """
      NIFs for reprojecting points with proj4. Inspiration from greenelephantlabs/proj4erl.
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
        checksum.exs
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
      {:elixir_make, "~> 0.9", runtime: false},
      {:cc_precompiler, "~> 0.1", runtime: false}
    ]
  end
end
