use apollo_compiler::ast::{Definition, Document, Selection};
use apollo_compiler::validation::DiagnosticList;
use apollo_compiler::validation::Valid;
use apollo_compiler::ExecutableDocument;
use apollo_compiler::Schema;
use std::collections::HashSet;

use regex::Regex;

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.ValidationError"]
pub struct ValidationError {
    pub message: String,
    pub locations: Vec<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.Location"]
pub struct Location {
    pub line: usize,
    pub column: usize,
    pub indentation: usize,
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

mod atoms {
    rustler::atoms! {
        ok,
        error,
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
                    indentation: 0,
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
                        indentation: 0,
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
                        indentation: 0,
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

fn validate_query_without_schema(
    query: String,
    path: String,
) -> Result<rustler::Atom, Vec<ValidationError>> {
    let document = parse_query(&query, &path)?;

    // Use apollo-compiler's standalone validation
    document
        .validate_standalone_executable()
        .map(|_| atoms::ok())
        .map_err(diagnostics_to_validation_errors)
}

fn validate_query_with_schema(
    schema: String,
    schema_path: String,
    query: String,
    path: String,
) -> Result<rustler::Atom, Vec<ValidationError>> {
    let schema = parse_schema(&schema, &schema_path)?;

    ExecutableDocument::parse_and_validate(&schema, query, path)
        .map(|_| atoms::ok())
        .map_err(|diagnostics| diagnostics_to_validation_errors(diagnostics.errors))
}

#[rustler::nif]
fn validate_query(
    query: String,
    path: String,
    schema: Option<String>,
    schema_path: Option<String>,
) -> Result<rustler::Atom, Vec<ValidationError>> {
    match schema {
        Some(schema) => {
            let schema_path = schema_path.unwrap_or_else(|| "schema.graphql".to_string());
            validate_query_with_schema(schema, schema_path, query, path)
        }
        None => validate_query_without_schema(query, path),
    }
}

#[rustler::nif]
fn validate_schema(schema: String, path: String) -> Result<rustler::Atom, Vec<ValidationError>> {
    parse_schema(&schema, &path).map(|_| atoms::ok())
}

#[rustler::nif]
fn validate_fragment(
    fragment: String,
    path: String,
    schema: Option<String>,
    schema_path: Option<String>,
) -> Result<rustler::Atom, Vec<ValidationError>> {
    let validation_result = match schema {
        Some(schema) => {
            let schema_path = schema_path.unwrap_or_else(|| "schema.graphql".to_string());
            validate_query_with_schema(schema, schema_path, fragment, path)
        }
        None => validate_query_without_schema(fragment, path),
    };

    let unused_fragment_regex = Regex::new(r"fragment `.*` must be used in an operation").unwrap();

    match validation_result {
        Ok(_) => Ok(atoms::ok()),
        Err(errors) => {
            let filtered_errors = errors
                .into_iter()
                .filter(|e| !unused_fragment_regex.is_match(&e.message))
                .collect::<Vec<ValidationError>>();

            if filtered_errors.is_empty() {
                Ok(atoms::ok())
            } else {
                Err(filtered_errors)
            }
        }
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
