defmodule GraphqlQuery.MixProject do
  use Mix.Project

  def project do
    [
      app: :graphql_query,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      rustler_crates: rustler_crates()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler, "~> 0.34"}
    ]
  end

  defp rustler_crates do
    [
      graphql_query_native: [
        path: "native/graphql_query_native",
        mode: rustler_mode()
      ]
    ]
  end

  defp rustler_mode do
    case Mix.env() do
      :prod -> :release
      _ -> :debug
    end
  end
end
