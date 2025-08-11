defmodule GraphqlQuery.Native do
  @moduledoc """
  Native interface to Rust functions for GraphQL query validation and formatting.
  """

  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:package][:links]["GitHub"]
  # Since Rustler 0.27.0, we need to change manually the mode for each env.
  # We want "debug" in dev and test because it's faster to compile.
  mode = if Mix.env() in [:dev, :test], do: :debug, else: :release

  use RustlerPrecompiled,
    otp_app: :graphql_query,
    crate: "graphql_query_native",
    base_url: "#{github_url}/releases/download/v#{version}",
    force_build: System.get_env("FORCE_BUILD") in ["1", "true"],
    mode: mode,
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-apple-darwin
      x86_64-pc-windows-msvc
      x86_64-pc-windows-gnu
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      x86_64-unknown-freebsd
    ),
    version: version

  @doc """
  Validates a GraphQL query string with a document path.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  def validate_query(_query, _path), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Formats a GraphQL query string.
  Returns {:ok, formatted_query} or {:error, reason}.
  """
  def format_query(_query), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Validates and formats a GraphQL query string in one call.
  Returns {:ok, {validated_query, formatted_query}} or {:error, reason}.
  """
  def validate_and_format_query(_query), do: :erlang.nif_error(:nif_not_loaded)
end
