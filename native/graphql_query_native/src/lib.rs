use apollo_compiler::ast::Document;
use apollo_compiler::validation::DiagnosticList;
use apollo_compiler::validation::Valid;
use apollo_compiler::ExecutableDocument;
use apollo_compiler::Schema;

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
                })
                .collect();

            ValidationError { message, locations }
        })
        .collect()
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
    let result = match schema {
        Some(schema) => {
            let schema_path = schema_path.unwrap_or_else(|| "schema.graphql".to_string());
            validate_query_with_schema(schema, schema_path, fragment, path)
        }
        None => validate_query_without_schema(fragment, path),
    };

    let unused_fragment_regex = Regex::new(r"fragment `.*` must be used in an operation").unwrap();

    match result {
        Ok(atom) => Ok(atom),
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
