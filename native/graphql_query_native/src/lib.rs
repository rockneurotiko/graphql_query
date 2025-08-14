use apollo_compiler::ast::Document;

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.Native.ValidationError"]
pub struct ValidationError {
    pub message: String,
    pub locations: Vec<Location>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "GraphqlQuery.Native.Location"]
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

fn parse_query(query: &str, path: &str) -> Result<Document, Vec<String>> {
    match Document::parse(query, path) {
        Ok(document) => Ok(document),
        Err(parse_result) => {
            let error_messages: Vec<String> = parse_result
                .errors
                .iter()
                .map(|err| format!("{err}"))
                .collect();
            Err(error_messages)
        }
    }
}

#[rustler::nif]
fn validate_query(query: String, path: String) -> Result<rustler::Atom, Vec<ValidationError>> {
    // Parse using apollo-compiler
    let document = match parse_query(&query, &path) {
        Ok(doc) => doc,
        Err(parse_errors) => {
            let validation_errors: Vec<ValidationError> = parse_errors
                .iter()
                .map(|err_msg| ValidationError {
                    message: err_msg.clone(),
                    locations: vec![],
                })
                .collect();
            return Err(validation_errors);
        }
    };

    // Use apollo-compiler's standalone validation
    match document.validate_standalone_executable() {
        Ok(_) => Ok(atoms::ok()),
        Err(validation_errors) => {
            let structured_errors: Vec<ValidationError> = validation_errors
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
                .collect();

            Err(structured_errors)
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

// Do not add the methods here, they are automatically added by Rustler
rustler::init!("Elixir.GraphqlQuery.Native");
