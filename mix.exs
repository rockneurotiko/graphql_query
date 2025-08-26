defmodule GraphqlQuery.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()
  @source_url "https://github.com/rockneurotiko/graphql_query"
  @dev? String.ends_with?(@version, "-dev")
  @force_build? System.get_env("FORCE_BUILD") in ["1", "true"]

  def project do
    [
      aliases: aliases(),
      app: :graphql_query,
      version: @version,
      description:
        "GraphQL Query provides compile-time and runtime safety for your GraphQL queries and schemas in Elixir.",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      package: package(),
      compilers: Mix.compilers()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:nimble_options, "~> 1.1"},
      {:jason, "~> 1.4", optional: true},

      # Development
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Release deps
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:iex, :mix],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp docs do
    [
      main: "GraphqlQuery",
      logo: "graphql_query_exdoc.png",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "docs/macros.md", "docs/cheatsheet.cheatmd"],
      groups_for_modules: [
        GraphqlQuery: [
          GraphqlQuery,
          GraphqlQuery.MacroOptions,
          GraphqlQuery.ValidationError,
          GraphqlQuery.Location,
          GraphqlQuery.Logger,
          GraphqlQuery.Parser,
          GraphqlQuery.Signature
        ],
        "GraphqlQuery Entities": [
          GraphqlQuery.Schema,
          GraphqlQuery.Document,
          GraphqlQuery.DocumentInfo,
          GraphqlQuery.QueryInfo,
          GraphqlQuery.Fragment,
          GraphqlQuery.FragmentInfo,
          GraphqlQuery.MutationInfo,
          GraphqlQuery.SubscriptionInfo
        ],
        Format: [
          GraphqlQuery.Formatter,
          GraphqlQuery.Format
        ],
        "Manual Validation": [
          GraphqlQuery.Validator
        ],
        Native: [
          GraphqlQuery.Native
        ]
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib/**/*.ex",
        "native/graphql_query_native/.cargo/config.toml",
        "native/graphql_query_native/*.lock",
        "native/graphql_query_native/*.toml",
        "native/graphql_query_native/src/**/*.rs",
        "checksum-*.exs",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "VERSION",
        "LICENSE"
      ],
      licenses: ["Beerware"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Rock Neurotiko"]
    ]
  end

  defp aliases do
    [
      "rust.lint": [
        "cmd cargo clippy --manifest-path=native/graphql_query_native/Cargo.toml -- -Dwarnings"
      ],
      "rust.fmt": ["cmd cargo fmt --manifest-path=native/graphql_query_native/Cargo.toml --all"],
      ci: [
        "compile --warnings-as-errors",
        "cmd mix test --warnings-as-errors",
        "credo",
        "dialyzer",
        "rust.lint",
        "rust.fmt"
      ]
    ]
  end
end
