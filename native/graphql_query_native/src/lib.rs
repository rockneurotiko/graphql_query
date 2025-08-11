use apollo_compiler::ast::Document;
use apollo_compiler::parser::Parser as ApolloCompilerParser;

mod atoms {
    rustler::atoms! {
        ok,
        error,
    }
}

fn parse_query(query: &str, path: &str) -> Result<Document, Vec<String>> {
    let mut parser = ApolloCompilerParser::new();
    match parser.parse_ast(query, path) {
        Ok(document) => Ok(document),
        Err(parse_result) => {
            let error_messages: Vec<String> = parse_result
                .errors
                .iter()
                .map(|err| format!("{}", err))
                .collect();
            Err(error_messages)
        }
    }
}

#[rustler::nif]
fn validate_query(query: String, path: String) -> Result<rustler::Atom, Vec<String>> {
    // Parse using apollo-compiler
    let document = match parse_query(&query, &path) {
        Ok(doc) => doc,
        Err(parse_errors) => return Err(parse_errors),
    };

    // Use apollo-compiler's standalone validation
    match document.validate_standalone_executable() {
        Ok(_) => Ok(atoms::ok()),
        Err(validation_errors) => {
            let error_messages: Vec<String> = validation_errors
                .iter()
                .map(|err| format!("{}", err))
                .collect();
            Err(error_messages)
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
    format!("{}", document)
}

// Do not add the methods here, they are automatically added by Rustler
rustler::init!("Elixir.GraphqlQuery.Native");
