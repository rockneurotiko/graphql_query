defmodule GraphqlQuery.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()
  @source_url "https://github.com/rockneurotiko/graphql_query"
  @dev? String.ends_with?(@version, "-dev")
  @force_build? System.get_env("FORCE_BUILD") in ["1", "true"]

  def project do
    [
      app: :graphql_query,
      version: @version,
      description: "GraphQL query validation and formatting utilities.",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      compilers: Mix.compilers()
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
      {:rustler_precompiled, "~> 0.8"},
      {:rustler, "~> 0.36.0", optional: not (@dev? or @force_build?)},

      # Release deps
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "GraphqlQuery",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "native/graphql_query_native/.cargo",
        "native/graphql_query_native/Cargo*",
        "native/graphql_query_native/src",
        "checksum-*.exs",
        "mix.exs",
        "README.md"
      ],
      licenses: ["Beerware"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Rock Neurotiko"]
    ]
  end
end
