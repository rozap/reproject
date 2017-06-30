defmodule Mix.Tasks.Compile.Reproject do
  @shortdoc "Compiles Reproject"

  def run(_) do
    IO.puts @shortdoc
    {result, _error_code} = System.cmd("make", ["priv/reproject.so"], stderr_to_stdout: true)
    Mix.shell.info result
  end
end

defmodule Reproject.Mixfile do
  use Mix.Project

  def project do
    [app: :reproject,
     version: "0.1.4",
     elixir: ">= 1.3.0 and <= 1.6.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     compilers: [:reproject, :elixir, :app],
     package: package(),
     description: description(),
     deps: deps()]
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

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end
end
