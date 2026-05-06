# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## [0.6.2]
### Fixed
- Fix escape in @deprecated reason correctly. By @fizzlebert

## [0.6.1]
### Fixed
- Warning line and column numbers are now accurate for all macro variants (`~GQL` sigil, `gql` heredoc, `gql` inline string, `gql_from_file`). Previously, line numbers were off by one due to a spurious `+1` in the offset calculation.
- Single-line `gql("...")` string arguments now correctly map errors to the call site line.
- `gql_from_file` errors now report lines relative to the external file rather than the call site.
- Runtime validation no longer double-formats error messages.

### Improved
- Validation errors originating in external fragments (passed via the `fragments:` option) now include context identifying the fragment name and line, and point to the `...FragmentName` spread in the query rather than the sigil line.
- Validation errors of the form `expected value of type X, found a variable` (produced by apollo-compiler when a variable is used for an input object field with an incompatible type) are now enriched with the variable name and its declared type, e.g.:

  ```text
  expected value of type ID!, found variable `$guid` of type `String!`
  ```
- Added `THIRD_PARTY_LICENSES.md` documenting the apollo-compiler dependency (MIT/Apache-2.0).

## [v0.6.0]
### Added
- Remote schema support: configure `use GraphqlQuery.Schema, remote: [url: "..."]` to manage schemas from external GraphQL APIs
- Mix tasks to fetch and check remote schemas: `graphql_query.schema.fetch` and `graphql_query.schema.check`

### Changed
- `use GraphqlQuery.Schema` now validates option combinations and raises `CompileError` for invalid combos (e.g., `:absinthe_schema` + `:remote`)
- Compile-time warning when remote schema file hasn't been fetched yet
- `GraphqlQuery.Schema.RemoteNotFetchedError` for graceful handling of missing remote schemas

## [v0.5.1]
### Fixed
- Check static values for `runtime` and `ignore` when other options are not static

## [v0.5.0]
### Breaking changes
- Now the library will warn if a query or fragment use @deprecated fields

### Fixed
- If a schema has warnings or errors, and they were ignored on the schema build, the queries/fragments that use the schema will ignore them too.
- If a schema imports directives with `@link` and also declares them, do not add them to the prelude, otherwise it fails with duplicated directive, but it's a valid use case. It also applies to scalars and enums.

## [v0.4.1]
- Update apollo library
- Make queries and fragments expand the schema before validation for `federation` schemas or option.

## [v0.4.0]
### Added
- Add `federation` and `F` options, this will read `@link` directive and add Apollo Federation directives based to parse and validate the schema

### Fixed
- When reading an absinthe schema, print the errors if there were some compilation error

## [v0.3.10]
### Changed
- Update apollo-compiler
- Change CI to use Elixir 1.19.2

## [v0.3.9]
### Fixed
- Expand path on `gql_from_file`. Fixes #16

### Changed
- `gql_from_file` needs a file path to be expanded on compile time. It will only read it once, even with runtime validation.

## [v0.3.8]
### Added
- Add `operationName` to json encoded data
- Add `c` option in sigil to set it as compile check

## [v0.3.7]

### Added
- `format` option for automatic query formatting when doing `to_string`

### Changed
- `gql_from_file` will try to expand the file_path before setting it in a module attribute

## [v0.3.6]

### Added
- Support for Absinthe schema extraction
- When options can't be expanded, it will use global runtime/ignore opts

### Changed
- Improved cheatsheet documentation with expanded examples
- Improved options resolution

## [v0.3.5]

### Added
- Documentation cheatsheet (`docs/cheatsheet.cheatmd`)
- Elixir macro documentation (`docs/macros.md`)

### Changed
- Enhanced macro options validation and processing
- Improved code organization and macro cleanup
- Enhanced option checking for better validation coverage

## [v0.3.4]

### Added
- Use DocumentInfo to try to extract a unique name (when there is only one document)
- Use DocumentInfo to detect multiple or non fragments defined when type is fragment and log a warning
- Use DocumentInfo to add only the extra fragments needed
- Create `GraphqlQuery.Logger` helper for compile-time and runtime logging
- Add `CHANGELOG.md` file
- Add a CI test to detect modules not added in the documentation

### Changed
- Add DocumentInfo on Document.new instead of validate.

## [v0.3.3]

### Added
- `document_with_options` macro for GraphQL document creation with custom options
- DocumentInfo support when parsing GraphQL documents for better validation context

### Changed
- Enhanced document parsing with document_info integration
- Improved documentation

### Fixed
- Fixed Dialyzer cache key issues

## [v0.3.2]

### Added
- Document and Fragment structs for better GraphQL document handling
- Support for specifying fragments on queries
- Improved Inspect protocol support for Elixir 1.19

### Changed
- Enhanced documentation with better examples and formatting
- Improved README with logo and better structure
- Better CI configuration and testing

### Fixed
- Fixed documentation module groupings in ExDoc
- Various documentation and formatting improvements

## [v0.3.1]

### Added
- Project logo and improved visual documentation
- Better documentation structure and examples

### Changed
- Enhanced documentation formatting and presentation
- Improved package metadata and descriptions

## [v0.3.0]

### Added
- Schema support for GraphQL validation
- Module compilation checks to ensure dependencies are loaded
- Expanded OTP version support

### Changed
- Relaxed version constraints for better compatibility
- Improved formatter and export functionality
- Better error handling and validation

### Fixed
- Fixed compatibility issues with various OTP versions
- Resolved clippy suggestions and code quality improvements

## [v0.2.0]

### Added
- `gql` macro for inline GraphQL query definition
- New macro system for better developer experience
- VERSION constant in mix.exs

### Changed
- Major refactor from function-based to macro-based API
- Improved parser implementation
- Enhanced README documentation with usage examples

### Fixed
- Fixed test suite after API changes
- Improved binary handling and parsing
- Better error messages and validation

## [v0.1.0]

### Added
- Initial release of GraphQL Query library
- Rust-based GraphQL parsing via Rustler NIFs
- Basic query validation and formatting functionality
- CI/CD workflow with GitHub Actions
- Rustler precompiled binaries support
