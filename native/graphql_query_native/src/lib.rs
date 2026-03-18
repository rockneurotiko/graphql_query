use apollo_compiler::ast::{Definition, Document, Selection};
use apollo_compiler::executable;
use apollo_compiler::schema::SchemaBuilder;
use apollo_compiler::validation::DiagnosticList;
use apollo_compiler::validation::Valid;
use apollo_compiler::ExecutableDocument;
use apollo_compiler::Schema;
use std::collections::HashSet;

use regex::Regex;

mod federation;

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.ValidationError"]
pub struct ValidationError {
    pub message: String,
    pub locations: Vec<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.ValidationWarning"]
pub struct ValidationWarning {
    pub kind: String,
    pub message: String,
    pub field: String,
    pub parent_type: String,
    pub locations: Vec<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.Location"]
pub struct Location {
    pub line: usize,
    pub column: usize,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.QueryInfo"]
pub struct QueryInfo {
    pub name: Option<String>,
    pub fragments: Vec<String>,
    pub location: Option<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.MutationInfo"]
pub struct MutationInfo {
    pub name: Option<String>,
    pub fragments: Vec<String>,
    pub location: Option<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.FragmentInfo"]
pub struct FragmentInfo {
    pub name: String,
    pub fragments: Vec<String>,
    pub location: Option<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.SubscriptionInfo"]
pub struct SubscriptionInfo {
    pub name: Option<String>,
    pub fragments: Vec<String>,
    pub location: Option<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.DocumentInfo"]
pub struct DocumentInfo {
    pub queries: Vec<QueryInfo>,
    pub mutations: Vec<MutationInfo>,
    pub fragments: Vec<FragmentInfo>,
    pub subscriptions: Vec<SubscriptionInfo>,
    pub signature: Option<String>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.SchemaInformation"]
pub struct SchemaInformation {
    pub schema: String,
    pub path: Option<String>,
    pub federation: bool,
    pub ignore_errors: bool,
}

/// Return type of `validate_document_with_schema`.
/// The `Err` variant is boxed to keep it small (avoids `clippy::result_large_err`).
type DocumentValidationResult = Result<
    (Valid<ExecutableDocument>, Vec<ValidationWarning>),
    Box<(ExecutableDocument, Vec<ValidationError>)>,
>;

/// Conditionally adds a federation prelude to a `SchemaBuilder`.
///
/// If `info.federation` is true and the schema contains a known `@link` federation
/// directive, generates the federation prelude SDL and appends it to the builder.
/// Returns the builder unchanged if federation is disabled, no known `@link` is found,
/// or AST parsing fails (build() will catch any errors later).
fn maybe_add_federation(info: &SchemaInformation, builder: SchemaBuilder) -> SchemaBuilder {
    if !info.federation {
        return builder;
    }

    let schema_path = info.path.as_deref().unwrap_or("schema.graphql");

    let Ok(document) = apollo_compiler::ast::Document::parse(&info.schema, schema_path) else {
        return builder;
    };

    let links = federation::extract_link_directives(&document);
    let fed_link = links
        .iter()
        .find(|l| l.spec.identity == federation::SpecIdentity::Federation);

    match fed_link {
        Some(link) if federation::is_known_version(&link.spec.version) => {
            let user_directives = federation::extract_user_directive_names(&document);
            let prelude = federation::generate_prelude(&links, &user_directives);
            builder.parse(&prelude, "federation_prelude.graphql")
        }
        _ => builder,
    }
}

/// Resolves a `SchemaInformation` into a `Valid<Schema>`.
///
/// Pipeline: parse schema → maybe add federation prelude → build → maybe validate.
/// When `ignore_errors` is true, both `build()` errors and `validate()` errors are
/// suppressed — the partial schema is used with `assume_valid`. This is safe because
/// the schema was already validated (or explicitly ignored) at its own compile time.
fn resolve_schema(info: &SchemaInformation) -> Result<Valid<Schema>, Vec<ValidationError>> {
    let schema_path = info.path.as_deref().unwrap_or("schema.graphql");

    let builder = maybe_add_federation(
        info,
        Schema::builder().parse(info.schema.to_string(), schema_path),
    );

    if info.ignore_errors {
        // When ignoring errors: use the partial schema even if build() fails
        let schema = match builder.build() {
            Ok(s) => s,
            Err(with_errors) => with_errors.partial,
        };
        Ok(Valid::assume_valid(schema))
    } else {
        let schema = builder
            .build()
            .map_err(|e| diagnostics_to_validation_errors(e.errors))?;

        schema
            .validate()
            .map_err(|e| diagnostics_to_validation_errors(e.errors))
    }
}

fn parse_query(query: &str, path: &str) -> Result<Document, Vec<ValidationError>> {
    Document::parse(query, path)
        .map_err(|parse_result| diagnostics_to_validation_errors(parse_result.errors))
}

fn parse_schema(schema: &str, path: &str) -> Result<Valid<Schema>, Vec<ValidationError>> {
    Schema::parse_and_validate(schema, path)
        .map_err(|errors| diagnostics_to_validation_errors(errors.errors))
}

/// Builds a `Valid<Schema>` with optional Apollo Federation support.
///
/// When `federation` is true, inspects the schema for `@link` directives pointing to a
/// known federation spec version and, if found, prepends a generated prelude SDL so that
/// federation directives (e.g. `@key`, `@external`) are recognised during validation.
/// Falls back to standard validation when no (or unknown) federation link is present.
///
/// Returning `Valid<Schema>` makes this helper reusable for both schema validation
/// (validate the schema itself) and query/fragment validation (validate an executable
/// document against the schema).
fn parse_schema_maybe_federation(
    schema_str: &str,
    schema_path: &str,
    federation: bool,
) -> Result<Valid<Schema>, Vec<ValidationError>> {
    if !federation {
        return parse_schema(schema_str, schema_path);
    }

    // 1. Parse the raw SDL to get the AST
    let document = apollo_compiler::ast::Document::parse(schema_str, schema_path)
        .map_err(|parse_result| diagnostics_to_validation_errors(parse_result.errors))?;

    // 2. Extract @link directives from schema definition
    let links = federation::extract_link_directives(&document);

    // 3. Find federation link
    let fed_link = links
        .iter()
        .find(|l| l.spec.identity == federation::SpecIdentity::Federation);

    // 4. If no federation @link found, fall back to standard validation
    if fed_link.is_none() {
        return parse_schema(schema_str, schema_path);
    }

    let fed_link = fed_link.unwrap();

    // 5. Validate we know this version, fall back if not
    if !federation::is_known_version(&fed_link.spec.version) {
        return parse_schema(schema_str, schema_path);
    }

    // 6. Extract user-defined directives and generate the prelude SDL, skipping any
    //    directives already declared in the user's schema (per-spec override support).
    let user_directives = federation::extract_user_directive_names(&document);
    let prelude = federation::generate_prelude(&links, &user_directives);

    // 7. Build schema with prelude + user SDL
    let schema = Schema::builder()
        .parse(&prelude, "federation_prelude.graphql")
        .parse(schema_str.to_string(), schema_path)
        .build()
        .map_err(|e| diagnostics_to_validation_errors(e.errors))?;

    // 8. Validate and return Valid<Schema>
    schema
        .validate()
        .map_err(|e| diagnostics_to_validation_errors(e.errors))
}

fn validate_schema_with_federation(
    schema_str: &str,
    path: &str,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    parse_schema_maybe_federation(schema_str, path, true).map(|_| vec![])
}

fn diagnostics_to_validation_errors(diagnostics: DiagnosticList) -> Vec<ValidationError> {
    diagnostics
        .iter()
        .map(|err| {
            let json_error = err.to_json();

            let message = json_error.message;
            let locations = json_error
                .locations
                .iter()
                .map(|loc| Location {
                    line: loc.line,
                    column: loc.column,
                })
                .collect();

            ValidationError { message, locations }
        })
        .collect()
}

fn extract_fragments_from_selection_set(selections: &[Selection], fragments: &mut HashSet<String>) {
    for selection in selections {
        match selection {
            Selection::Field(field) => {
                extract_fragments_from_selection_set(&field.selection_set, fragments);
            }
            Selection::InlineFragment(inline_fragment) => {
                extract_fragments_from_selection_set(&inline_fragment.selection_set, fragments);
            }
            Selection::FragmentSpread(fragment_spread) => {
                fragments.insert(fragment_spread.fragment_name.to_string());
            }
        }
    }
}

fn extract_operation_info(document: &Document) -> DocumentInfo {
    let mut queries = Vec::new();
    let mut mutations = Vec::new();
    let mut subscriptions = Vec::new();
    let mut fragments = Vec::new();

    for definition in &document.definitions {
        match definition {
            Definition::OperationDefinition(op) => {
                let mut used_fragments = HashSet::new();
                extract_fragments_from_selection_set(&op.selection_set, &mut used_fragments);

                let operation_name = op.name.as_ref().map(|n| n.to_string());
                let used_fragments_vec: Vec<String> = used_fragments.into_iter().collect();
                let location = definition
                    .location()
                    .and_then(|loc| loc.line_column(&document.sources))
                    .map(|location| Location {
                        line: location.line,
                        column: location.column,
                    });

                match op.operation_type {
                    apollo_compiler::ast::OperationType::Query => {
                        queries.push(QueryInfo {
                            name: operation_name,
                            fragments: used_fragments_vec,
                            location,
                        });
                    }
                    apollo_compiler::ast::OperationType::Mutation => {
                        mutations.push(MutationInfo {
                            name: operation_name,
                            fragments: used_fragments_vec,
                            location,
                        });
                    }
                    apollo_compiler::ast::OperationType::Subscription => {
                        subscriptions.push(SubscriptionInfo {
                            name: operation_name,
                            fragments: used_fragments_vec,
                            location,
                        });
                    }
                }
            }
            // Fragment information is already handled by extract_fragment_info
            Definition::FragmentDefinition(frag) => {
                let mut used_fragments = HashSet::new();
                extract_fragments_from_selection_set(&frag.selection_set, &mut used_fragments);
                let location = definition
                    .location()
                    .and_then(|loc| loc.line_column(&document.sources))
                    .map(|location| Location {
                        line: location.line,
                        column: location.column,
                    });

                fragments.push(FragmentInfo {
                    name: frag.name.to_string(),
                    fragments: used_fragments.into_iter().collect(),
                    location,
                });
            }
            _ => {}
        }
    }

    DocumentInfo {
        queries,
        mutations,
        fragments,
        subscriptions,
        signature: None,
    }
}

#[rustler::nif]
fn document_information(
    document: String,
    path: String,
) -> Result<DocumentInfo, Vec<ValidationError>> {
    parse_query(&document, &path).map(|doc| extract_operation_info(&doc))
}

fn collect_deprecated_field_warnings(document: &ExecutableDocument) -> Vec<ValidationWarning> {
    let mut warnings = Vec::new();
    let mut visited_fragments: HashSet<String> = HashSet::new();

    // Walk all named operations
    for (_name, operation) in &document.operations.named {
        collect_warnings_from_selection_set(
            &operation.selection_set,
            document,
            &mut warnings,
            &mut visited_fragments,
        );
    }

    // Walk anonymous operation if present
    if let Some(operation) = &document.operations.anonymous {
        collect_warnings_from_selection_set(
            &operation.selection_set,
            document,
            &mut warnings,
            &mut visited_fragments,
        );
    }

    // Walk top-level fragment definitions (for standalone fragment validation)
    for (name, fragment) in &document.fragments {
        if !visited_fragments.contains(name.as_str()) {
            visited_fragments.insert(name.to_string());
            collect_warnings_from_selection_set(
                &fragment.selection_set,
                document,
                &mut warnings,
                &mut visited_fragments,
            );
        }
    }

    warnings
}

fn collect_warnings_from_selection_set(
    selection_set: &executable::SelectionSet,
    document: &ExecutableDocument,
    warnings: &mut Vec<ValidationWarning>,
    visited_fragments: &mut HashSet<String>,
) {
    let parent_type = selection_set.ty.as_str().to_string();

    for selection in &selection_set.selections {
        match selection {
            executable::Selection::Field(node_field) => {
                let field_def = &node_field.definition;

                // Check if the field definition has a @deprecated directive
                let deprecated_directive =
                    field_def.directives.iter().find(|d| d.name == "deprecated");

                if let Some(directive) = deprecated_directive {
                    let reason = directive
                        .specified_argument_by_name("reason")
                        .and_then(|v| {
                            if let apollo_compiler::ast::Value::String(s) = v.as_ref() {
                                Some(s.as_str().to_string())
                            } else {
                                None
                            }
                        })
                        .unwrap_or_else(|| "".to_string());

                    let locations = node_field
                        .location()
                        .and_then(|loc| loc.line_column(&document.sources))
                        .map(|lc| {
                            vec![Location {
                                line: lc.line,
                                column: lc.column,
                            }]
                        })
                        .unwrap_or_default();

                    warnings.push(ValidationWarning {
                        kind: "deprecated_field".to_string(),
                        message: reason,
                        field: node_field.name.to_string(),
                        parent_type: parent_type.clone(),
                        locations,
                    });
                }

                // Recurse into sub-selections
                collect_warnings_from_selection_set(
                    &node_field.selection_set,
                    document,
                    warnings,
                    visited_fragments,
                );
            }
            executable::Selection::InlineFragment(inline) => {
                collect_warnings_from_selection_set(
                    &inline.selection_set,
                    document,
                    warnings,
                    visited_fragments,
                );
            }
            executable::Selection::FragmentSpread(spread) => {
                let frag_name = spread.fragment_name.as_str().to_string();
                if !visited_fragments.contains(&frag_name) {
                    visited_fragments.insert(frag_name.clone());
                    if let Some(fragment) = document.fragments.get(&spread.fragment_name) {
                        collect_warnings_from_selection_set(
                            &fragment.selection_set,
                            document,
                            warnings,
                            visited_fragments,
                        );
                    }
                }
            }
        }
    }
}

fn validate_query_without_schema(
    query: String,
    path: String,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    let document = parse_query(&query, &path)?;

    // Use apollo-compiler's standalone validation
    document
        .validate_standalone_executable()
        .map(|_| vec![])
        .map_err(diagnostics_to_validation_errors)
}

/// Parses a schema (via `resolve_schema`) and validates an executable document against it.
/// Returns `Ok((document, warnings))` on success, or `Err((partial_document, errors))`
/// if there are validation errors. The partial document is included on failure so callers
/// can still inspect it (e.g. to collect deprecation warnings despite "unused fragment" errors).
fn validate_document_with_schema(
    schema_info: &SchemaInformation,
    query: String,
    path: String,
) -> DocumentValidationResult {
    let schema = resolve_schema(schema_info).map_err(|errors| {
        // Schema parse/build failure: no document available
        Box::new((ExecutableDocument::default(), errors))
    })?;

    match ExecutableDocument::parse_and_validate(&schema, query, path) {
        Ok(valid_doc) => {
            let warnings = collect_deprecated_field_warnings(&valid_doc);
            Ok((valid_doc, warnings))
        }
        Err(with_errors) => {
            let errors = diagnostics_to_validation_errors(with_errors.errors);
            Err(Box::new((with_errors.partial, errors)))
        }
    }
}

fn validate_query_with_schema(
    schema_info: &SchemaInformation,
    query: String,
    path: String,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    validate_document_with_schema(schema_info, query, path)
        .map(|(_, warnings)| warnings)
        .map_err(|e| e.1)
}

#[rustler::nif]
fn validate_query(
    query: String,
    path: String,
    schema_info: Option<SchemaInformation>,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    match schema_info {
        Some(ref info) => validate_query_with_schema(info, query, path),
        None => validate_query_without_schema(query, path),
    }
}

#[rustler::nif]
fn validate_schema(
    schema: String,
    path: String,
    federation: bool,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    if federation {
        validate_schema_with_federation(&schema, &path)
    } else {
        parse_schema(&schema, &path).map(|_| vec![])
    }
}

#[rustler::nif]
fn validate_fragment(
    fragment: String,
    path: String,
    schema_info: Option<SchemaInformation>,
) -> Result<Vec<ValidationWarning>, Vec<ValidationError>> {
    let unused_fragment_regex = Regex::new(r"fragment `.*` must be used in an operation").unwrap();

    match schema_info {
        Some(ref info) => {
            match validate_document_with_schema(info, fragment, path) {
                Ok((_, warnings)) => Ok(warnings),
                Err(boxed) => {
                    let (partial_doc, errors) = *boxed;
                    let filtered_errors: Vec<ValidationError> = errors
                        .into_iter()
                        .filter(|e| !unused_fragment_regex.is_match(&e.message))
                        .collect();

                    if filtered_errors.is_empty() {
                        // The only errors were "unused fragment" — still collect deprecation warnings
                        // from the partial document (which has the fragment's selections).
                        let warnings = collect_deprecated_field_warnings(&partial_doc);
                        Ok(warnings)
                    } else {
                        Err(filtered_errors)
                    }
                }
            }
        }
        None => match validate_query_without_schema(fragment, path) {
            Ok(warnings) => Ok(warnings),
            Err(errors) => {
                let filtered_errors: Vec<ValidationError> = errors
                    .into_iter()
                    .filter(|e| !unused_fragment_regex.is_match(&e.message))
                    .collect();

                if filtered_errors.is_empty() {
                    Ok(vec![])
                } else {
                    Err(filtered_errors)
                }
            }
        },
    }
}

#[rustler::nif]
fn format_query(query: String) -> String {
    let document = match parse_query(&query, "query") {
        Ok(doc) => doc,
        Err(_parse_errors) => {
            // Return original query if parsing failed
            return query;
        }
    };

    // Use apollo_compiler's built-in Display trait for formatting
    format!("{document}")
}

#[rustler::nif]
fn format_schema(schema: String) -> String {
    let document = match parse_schema(&schema, "schema") {
        Ok(schema) => schema,
        _ => {
            return schema;
        }
    };

    // Use apollo_compiler's built-in Display trait for formatting
    format!("{document}")
}

// Do not add the methods here, they are automatically added by Rustler
rustler::init!("Elixir.GraphqlQuery.Native");

#[cfg(test)]
mod tests {
    use super::*;

    // ---------------------------------------------------------------------------
    // Shared schema fixtures
    // ---------------------------------------------------------------------------

    /// A plain (non-federation) schema.
    fn plain_schema() -> &'static str {
        r#"
        type Query {
            user(id: ID!): User
            product(id: ID!): Product
        }

        type User {
            id: ID!
            name: String!
            email: String!
        }

        type Product {
            id: ID!
            title: String!
        }
        "#
    }

    /// A federation v2 schema with @key and @shareable.
    fn federation_schema() -> &'static str {
        r#"
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

        type Query {
            user(id: ID!): User
            product(id: ID!): Product
        }

        type User @key(fields: "id") {
            id: ID!
            name: String! @shareable
            email: String!
        }

        type Product @key(fields: "id") {
            id: ID!
            title: String! @shareable
        }
        "#
    }

    /// A federation v2 schema with @external and @requires.
    fn federation_schema_with_external() -> &'static str {
        r#"
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@external", "@requires"])

        type Query {
            user(id: ID!): User
        }

        type User @key(fields: "id") {
            id: ID!
            name: String! @external
            greeting: String! @requires(fields: "name")
        }
        "#
    }

    // ---------------------------------------------------------------------------
    // parse_schema_maybe_federation — federation: false
    // ---------------------------------------------------------------------------

    #[test]
    fn test_parse_schema_maybe_federation_false_valid_schema() {
        let result = parse_schema_maybe_federation(plain_schema(), "schema.graphql", false);
        assert!(result.is_ok(), "expected Ok, got: {:?}", result.err());
    }

    #[test]
    fn test_parse_schema_maybe_federation_false_invalid_schema() {
        let bad_schema = "type Query { broken(";
        let result = parse_schema_maybe_federation(bad_schema, "schema.graphql", false);
        assert!(result.is_err(), "expected Err for invalid schema");
        assert!(!result.unwrap_err().is_empty());
    }

    // ---------------------------------------------------------------------------
    // parse_schema_maybe_federation — federation: true, plain schema falls back
    // ---------------------------------------------------------------------------

    #[test]
    fn test_parse_schema_maybe_federation_true_plain_schema_fallback() {
        // A plain schema with no @link → should fall back to standard validation and succeed
        let result = parse_schema_maybe_federation(plain_schema(), "schema.graphql", true);
        assert!(
            result.is_ok(),
            "expected Ok for plain schema fallback, got: {:?}",
            result.err()
        );
    }

    // ---------------------------------------------------------------------------
    // parse_schema_maybe_federation — federation: true, federation schema
    // ---------------------------------------------------------------------------

    #[test]
    fn test_parse_schema_maybe_federation_true_federation_schema() {
        let result = parse_schema_maybe_federation(federation_schema(), "schema.graphql", true);
        assert!(
            result.is_ok(),
            "expected Ok for federation schema, got: {:?}",
            result.err()
        );
    }

    #[test]
    fn test_parse_schema_maybe_federation_true_directives_recognised() {
        // Without federation=true, @key/@shareable are unknown directives → error.
        // With federation=true the prelude is injected → success.
        let result_plain =
            parse_schema_maybe_federation(federation_schema(), "schema.graphql", false);
        let result_fed = parse_schema_maybe_federation(federation_schema(), "schema.graphql", true);

        assert!(
            result_plain.is_err(),
            "expected Err without federation support"
        );
        assert!(
            result_fed.is_ok(),
            "expected Ok with federation support, got: {:?}",
            result_fed.err()
        );
    }

    #[test]
    fn test_parse_schema_maybe_federation_external_and_requires() {
        let result = parse_schema_maybe_federation(
            federation_schema_with_external(),
            "schema.graphql",
            true,
        );
        assert!(
            result.is_ok(),
            "expected Ok for @external/@requires, got: {:?}",
            result.err()
        );
    }

    #[test]
    fn test_parse_schema_maybe_federation_unknown_version_fallback() {
        // Unknown federation version → falls back to plain parse, which fails because
        // @key is still an unknown directive at that point.
        let schema = r#"
            extend schema @link(url: "https://specs.apollo.dev/federation/v99.0", import: ["@key"])

            type Query { user: User }
            type User @key(fields: "id") { id: ID! }
        "#;

        let result = parse_schema_maybe_federation(schema, "schema.graphql", true);
        assert!(
            result.is_err(),
            "expected Err for unknown federation version fallback"
        );
    }

    // ---------------------------------------------------------------------------
    // Query validation against a schema — the core of the new feature.
    //
    // validate_query_with_schema returns Result<rustler::Atom, Vec<ValidationError>>.
    // We cannot call rustler::Atom constructors outside the BEAM, so we test the
    // underlying schema-building helper (parse_schema_maybe_federation) directly,
    // and then run ExecutableDocument::parse_and_validate against the resulting
    // Valid<Schema> — exactly replicating what validate_query_with_schema does.
    // ---------------------------------------------------------------------------

    fn run_query_against_schema(
        schema_str: &str,
        schema_path: &str,
        query: &str,
        query_path: &str,
        federation: bool,
    ) -> Result<(), Vec<ValidationError>> {
        let info = SchemaInformation {
            schema: schema_str.to_string(),
            path: Some(schema_path.to_string()),
            federation,
            ignore_errors: false,
        };
        let schema = resolve_schema(&info)?;

        ExecutableDocument::parse_and_validate(&schema, query, query_path)
            .map(|_| ())
            .map_err(|d| diagnostics_to_validation_errors(d.errors))
    }

    #[test]
    fn test_query_valid_against_plain_schema() {
        let query = r#"query GetUser($id: ID!) { user(id: $id) { id name email } }"#;
        let result = run_query_against_schema(
            plain_schema(),
            "schema.graphql",
            query,
            "query.graphql",
            false,
        );
        assert!(result.is_ok(), "expected Ok, got: {:?}", result.err());
    }

    #[test]
    fn test_query_nonexistent_field_plain_schema() {
        let query = r#"query GetUser { user(id: "1") { id nonExistentField } }"#;
        let result = run_query_against_schema(
            plain_schema(),
            "schema.graphql",
            query,
            "query.graphql",
            false,
        );
        assert!(result.is_err(), "expected Err for nonexistent field");
        assert!(result
            .unwrap_err()
            .iter()
            .any(|e| e.message.contains("nonExistentField")));
    }

    #[test]
    fn test_query_valid_against_federation_schema() {
        let query = r#"query GetUser($id: ID!) { user(id: $id) { id name email } }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            query,
            "query.graphql",
            true,
        );
        assert!(result.is_ok(), "expected Ok, got: {:?}", result.err());
    }

    #[test]
    fn test_query_nonexistent_field_federation_schema() {
        let query = r#"query GetUser { user(id: "1") { id ghostField } }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            query,
            "query.graphql",
            true,
        );
        assert!(result.is_err(), "expected Err for nonexistent field");
        assert!(result
            .unwrap_err()
            .iter()
            .any(|e| e.message.contains("ghostField")));
    }

    #[test]
    fn test_query_without_federation_flag_fails_on_federation_schema() {
        // Schema parse fails because @key/@shareable are unknown → schema build error.
        let query = r#"query GetUser($id: ID!) { user(id: $id) { id name } }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            query,
            "query.graphql",
            false,
        );
        assert!(
            result.is_err(),
            "expected Err: federation schema requires federation=true"
        );
    }

    // ---------------------------------------------------------------------------
    // Fragment validation against a federation schema.
    // Same helper; the NIF layer filters "unused fragment" errors separately.
    // ---------------------------------------------------------------------------

    #[test]
    fn test_fragment_valid_against_federation_schema() {
        let fragment = r#"fragment UserFields on User { id name email }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            fragment,
            "fragment.graphql",
            true,
        );
        // The raw validation returns "unused fragment" error — that's expected and
        // filtered by the NIF wrapper. All other errors must be absent.
        match result {
            Ok(_) => {}
            Err(errors) => {
                let real_errors: Vec<_> = errors
                    .iter()
                    .filter(|e| !e.message.contains("must be used in an operation"))
                    .collect();
                assert!(
                    real_errors.is_empty(),
                    "unexpected errors: {:?}",
                    real_errors
                );
            }
        }
    }

    #[test]
    fn test_fragment_nonexistent_field_federation_schema() {
        let fragment = r#"fragment UserFields on User { id name ghostField }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            fragment,
            "fragment.graphql",
            true,
        );
        assert!(
            result.is_err(),
            "expected Err for nonexistent field in fragment"
        );
        let errors = result.unwrap_err();
        let real_errors: Vec<_> = errors
            .iter()
            .filter(|e| !e.message.contains("must be used in an operation"))
            .collect();
        assert!(!real_errors.is_empty(), "expected at least one real error");
        assert!(real_errors.iter().any(|e| e.message.contains("ghostField")));
    }

    #[test]
    fn test_fragment_without_federation_flag_fails_on_federation_schema() {
        let fragment = r#"fragment UserFields on User { id name }"#;
        let result = run_query_against_schema(
            federation_schema(),
            "schema.graphql",
            fragment,
            "fragment.graphql",
            false,
        );
        assert!(
            result.is_err(),
            "expected Err: federation schema requires federation=true"
        );
    }

    #[test]
    fn test_fragment_external_field_valid_on_federation_schema() {
        // @external fields are still selectable in queries/fragments
        let fragment = r#"fragment UserFields on User { id name greeting }"#;
        let result = run_query_against_schema(
            federation_schema_with_external(),
            "schema.graphql",
            fragment,
            "fragment.graphql",
            true,
        );
        match result {
            Ok(_) => {}
            Err(errors) => {
                let real_errors: Vec<_> = errors
                    .iter()
                    .filter(|e| !e.message.contains("must be used in an operation"))
                    .collect();
                assert!(
                    real_errors.is_empty(),
                    "unexpected errors: {:?}",
                    real_errors
                );
            }
        }
    }
}
