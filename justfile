manifest-path := "./native/graphql_query_native/Cargo.toml"

[group('general')]
list:
    @just --list

[group('general')]
elixir-deps:
    mix deps.get

[group('general')]
rust-deps:
    cargo fetch --manifest-path={{manifest-path}}

[parallel]
[group('general')]
deps: elixir-deps rust-deps

[group('general')]
elixir-compile: elixir-deps
    mix compile --warnings-as-errors

[group('general')]
rust-compile: rust-deps
    cargo build --manifest-path={{manifest-path}} --all

[parallel]
[group('general')]
compile: elixir-compile rust-compile

[group('test')]
elixir-test:
    mix test --warnings-as-errors

[group('test')]
rust-test:
    cargo test --manifest-path={{manifest-path}}

[group('test')]
test: elixir-test rust-test

[group('format')]
rust-format:
    cargo fmt --manifest-path={{manifest-path}} --all -- --check

[group('format')]
elixir-format:
    mix format --check-formatted

[parallel]
[group('format')]
format: rust-format elixir-format

[group('lint')]
credo:
    mix credo --strict

[group('lint')]
dialyzer:
    mix dialyzer

[group('lint')]
clippy:
    cargo clippy --manifest-path={{manifest-path}} --all -- -Dwarnings

[group('lint')]
docs-check-modules:
    ./bin/check_modules_docs.sh

[private]
[parallel]
[group('lint')]
lint-checks: credo dialyzer clippy docs-check-modules

[group('lint')]
lint: compile format lint-checks
