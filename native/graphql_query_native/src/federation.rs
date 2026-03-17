use apollo_compiler::ast::{Definition, Document, Value};
use apollo_compiler::Node;
use regex::Regex;
use std::collections::{HashMap, HashSet};

/// Identifies which spec a @link directive points to
#[derive(Debug, Clone, PartialEq)]
pub enum SpecIdentity {
    Federation,
    Link,
    Unknown,
}

/// Parsed information from a @link URL
#[derive(Debug, Clone)]
pub struct LinkSpec {
    pub name: Option<String>,
    pub version: Option<String>,
    pub identity: SpecIdentity,
}

/// A single import entry from the import argument
#[derive(Debug, Clone)]
pub struct ImportEntry {
    pub original_name: String, // e.g., "key" (without @)
    pub local_name: String,    // e.g., "primaryKey" (without @)
    pub is_directive: bool,    // true if starts with @
}

/// A parsed @link directive with all its arguments
#[derive(Debug, Clone)]
pub struct LinkDirective {
    #[allow(dead_code)]
    pub url: String,
    pub spec: LinkSpec,
    pub prefix: String,
    pub imports: Vec<ImportEntry>,
}

/// Federation directive definition metadata
#[derive(Debug, Clone)]
struct FederationDirective {
    name: &'static str,
    arguments: &'static str,
    locations: &'static str,
    repeatable: bool,
    #[allow(dead_code)]
    min_version: &'static str,
}

/// Parse a @link URL to extract spec name, version, and identity
pub fn parse_link_url(url: &str) -> LinkSpec {
    // Strip trailing slashes, query strings, fragments
    let url = url.trim_end_matches('/');
    let url = url.split('?').next().unwrap_or(url);
    let url = url.split('#').next().unwrap_or(url);

    // Split into path segments
    let segments: Vec<&str> = url.split('/').filter(|s| !s.is_empty()).collect();

    if segments.len() < 2 {
        return LinkSpec {
            name: None,
            version: None,
            identity: SpecIdentity::Unknown,
        };
    }

    // Check for version in last segment (e.g., "v2.3")
    let version_regex = Regex::new(r"^v\d+\.\d+$").unwrap();
    let (version, name_segment_idx) = if version_regex.is_match(segments[segments.len() - 1]) {
        (
            Some(segments[segments.len() - 1].to_string()),
            segments.len() - 2,
        )
    } else {
        (None, segments.len() - 1)
    };

    // Get the spec name from the penultimate segment (or last if no version)
    let name = if name_segment_idx < segments.len() {
        let name_candidate = segments[name_segment_idx];
        // Validate it's a valid GraphQL name (no __, no leading/trailing _)
        if is_valid_graphql_name(name_candidate) {
            Some(name_candidate.to_string())
        } else {
            None
        }
    } else {
        None
    };

    // Determine identity based on known patterns
    let identity = if url.contains("specs.apollo.dev/federation") {
        SpecIdentity::Federation
    } else if url.contains("specs.apollo.dev/link") {
        SpecIdentity::Link
    } else {
        SpecIdentity::Unknown
    };

    LinkSpec {
        name,
        version,
        identity,
    }
}

fn is_valid_graphql_name(s: &str) -> bool {
    if s.is_empty() || s.starts_with('_') || s.ends_with('_') || s.contains("__") {
        return false;
    }
    // Simple check: alphanumeric + underscore, starts with letter
    s.chars().all(|c| c.is_alphanumeric() || c == '_')
        && s.chars().next().is_some_and(|c| c.is_alphabetic())
}

/// Extract all @link directives from a schema document
pub fn extract_link_directives(document: &Document) -> Vec<LinkDirective> {
    let mut link_directives = Vec::new();

    for definition in &document.definitions {
        let directives = match definition {
            Definition::SchemaDefinition(schema_def) => Some(&schema_def.directives),
            Definition::SchemaExtension(schema_ext) => Some(&schema_ext.directives),
            _ => None,
        };

        if let Some(directives) = directives {
            for directive in directives {
                if directive.name == "link" {
                    if let Some(link) = parse_link_directive(directive) {
                        link_directives.push(link);
                    }
                }
            }
        }
    }

    link_directives
}

/// Extract the names of all directives explicitly defined in the user's schema document.
///
/// This is used to avoid re-emitting prelude directive definitions that the user has
/// already declared themselves — which the GraphQL spec allows so that engines that
/// don't handle `@link` imports correctly can still validate the schema.
pub fn extract_user_directive_names(document: &Document) -> HashSet<String> {
    document
        .definitions
        .iter()
        .filter_map(|def| {
            if let Definition::DirectiveDefinition(d) = def {
                Some(d.name.to_string())
            } else {
                None
            }
        })
        .collect()
}

/// Parse a single @link directive into a LinkDirective struct
fn parse_link_directive(directive: &apollo_compiler::ast::Directive) -> Option<LinkDirective> {
    // Extract the url argument
    let url = directive
        .arguments
        .iter()
        .find(|arg| arg.name == "url")
        .and_then(|arg| match &*arg.value {
            Value::String(s) => Some(s.as_str()),
            _ => None,
        })?;

    let spec = parse_link_url(url);

    // Extract the "as" argument (namespace prefix override)
    let prefix = directive
        .arguments
        .iter()
        .find(|arg| arg.name == "as")
        .and_then(|arg| match &*arg.value {
            Value::String(s) => Some(s.clone()),
            _ => None,
        })
        .or_else(|| spec.name.clone())
        .unwrap_or_else(|| "unknown".to_string());

    // Extract the "import" argument
    let imports = directive
        .arguments
        .iter()
        .find(|arg| arg.name == "import")
        .map(|arg| parse_import_argument(&arg.value))
        .unwrap_or_default();

    Some(LinkDirective {
        url: url.to_string(),
        spec,
        prefix,
        imports,
    })
}

/// Parse the import argument value into a list of ImportEntry
fn parse_import_argument(value: &Node<Value>) -> Vec<ImportEntry> {
    match &**value {
        Value::List(items) => items.iter().filter_map(parse_import_item).collect(),
        _ => Vec::new(),
    }
}

/// Parse a single import item (either a string or an object)
fn parse_import_item(value: &Node<Value>) -> Option<ImportEntry> {
    match &**value {
        // String form: "@key" or "FieldSet"
        Value::String(s) => {
            let is_directive = s.starts_with('@');
            let name = if is_directive {
                s.strip_prefix('@').unwrap_or(s)
            } else {
                s.as_str()
            };
            Some(ImportEntry {
                original_name: name.to_string(),
                local_name: name.to_string(),
                is_directive,
            })
        }
        // Object form: {name: "@key", as: "@primaryKey"}
        Value::Object(obj) => {
            let name =
                obj.iter()
                    .find(|(k, _)| k.as_str() == "name")
                    .and_then(|(_, v)| match &**v {
                        Value::String(s) => Some(s.as_str()),
                        _ => None,
                    })?;

            let is_directive = name.starts_with('@');
            let original_name = if is_directive {
                name.strip_prefix('@').unwrap_or(name)
            } else {
                name
            };

            let local_name = obj
                .iter()
                .find(|(k, _)| k.as_str() == "as")
                .and_then(|(_, v)| match &**v {
                    Value::String(s) => Some(s.as_str()),
                    _ => None,
                })
                .unwrap_or(name);

            let local_name = if local_name.starts_with('@') {
                local_name.strip_prefix('@').unwrap_or(local_name)
            } else {
                local_name
            };

            Some(ImportEntry {
                original_name: original_name.to_string(),
                local_name: local_name.to_string(),
                is_directive,
            })
        }
        _ => None,
    }
}

/// Get the list of federation directives available for a given version
fn get_federation_directives(version: &str) -> Vec<FederationDirective> {
    let mut directives = vec![
        // v2.0 directives
        FederationDirective {
            name: "key",
            arguments: "(fields: FieldSet!, resolvable: Boolean = true)",
            locations: "OBJECT | INTERFACE",
            repeatable: true,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "requires",
            arguments: "(fields: FieldSet!)",
            locations: "FIELD_DEFINITION",
            repeatable: false,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "provides",
            arguments: "(fields: FieldSet!)",
            locations: "FIELD_DEFINITION",
            repeatable: false,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "external",
            arguments: "",
            locations: "FIELD_DEFINITION | OBJECT",
            repeatable: false,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "tag",
            arguments: "(name: String!)",
            locations: "FIELD_DEFINITION | OBJECT | INTERFACE | UNION | ARGUMENT_DEFINITION | SCALAR | ENUM | ENUM_VALUE | INPUT_OBJECT | INPUT_FIELD_DEFINITION | SCHEMA",
            repeatable: true,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "extends",
            arguments: "",
            locations: "OBJECT | INTERFACE",
            repeatable: false,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "shareable",
            arguments: "",
            locations: "FIELD_DEFINITION | OBJECT",
            repeatable: version_gte(version, "v2.2"),
            min_version: "v2.0",
        },
        FederationDirective {
            name: "inaccessible",
            arguments: "",
            locations: "FIELD_DEFINITION | OBJECT | INTERFACE | UNION | ARGUMENT_DEFINITION | SCALAR | ENUM | ENUM_VALUE | INPUT_OBJECT | INPUT_FIELD_DEFINITION",
            repeatable: false,
            min_version: "v2.0",
        },
        FederationDirective {
            name: "override",
            arguments: if version_gte(version, "v2.7") {
                "(from: String!, label: String)"
            } else {
                "(from: String!)"
            },
            locations: "FIELD_DEFINITION",
            repeatable: false,
            min_version: "v2.0",
        },
    ];

    // v2.1+
    if version_gte(version, "v2.1") {
        directives.push(FederationDirective {
            name: "composeDirective",
            arguments: "(name: String!)",
            locations: "SCHEMA",
            repeatable: true,
            min_version: "v2.1",
        });
    }

    // v2.3+
    if version_gte(version, "v2.3") {
        directives.push(FederationDirective {
            name: "interfaceObject",
            arguments: "",
            locations: "OBJECT",
            repeatable: false,
            min_version: "v2.3",
        });
    }

    // v2.5+
    if version_gte(version, "v2.5") {
        directives.push(FederationDirective {
            name: "authenticated",
            arguments: "",
            locations: "FIELD_DEFINITION | OBJECT | INTERFACE | SCALAR | ENUM",
            repeatable: false,
            min_version: "v2.5",
        });
        directives.push(FederationDirective {
            name: "requiresScopes",
            arguments: "(scopes: [[federation__Scope!]!]!)",
            locations: "FIELD_DEFINITION | OBJECT | INTERFACE | SCALAR | ENUM",
            repeatable: false,
            min_version: "v2.5",
        });
    }

    // v2.6+
    if version_gte(version, "v2.6") {
        directives.push(FederationDirective {
            name: "policy",
            arguments: "(policies: [[federation__Policy!]!]!)",
            locations: "FIELD_DEFINITION | OBJECT | INTERFACE | SCALAR | ENUM",
            repeatable: false,
            min_version: "v2.6",
        });
    }

    // v2.8+
    if version_gte(version, "v2.8") {
        directives.push(FederationDirective {
            name: "context",
            arguments: "(name: String!)",
            locations: "OBJECT | INTERFACE | UNION",
            repeatable: true,
            min_version: "v2.8",
        });
        directives.push(FederationDirective {
            name: "fromContext",
            arguments: "(field: ContextFieldValue)",
            locations: "ARGUMENT_DEFINITION",
            repeatable: false,
            min_version: "v2.8",
        });
    }

    // v2.9+
    if version_gte(version, "v2.9") {
        directives.push(FederationDirective {
            name: "cost",
            arguments: "(weight: Int!)",
            locations: "FIELD_DEFINITION | ARGUMENT_DEFINITION | SCALAR | ENUM",
            repeatable: false,
            min_version: "v2.9",
        });
        directives.push(FederationDirective {
            name: "listSize",
            arguments: "(assumedSize: Int, slicingArguments: [String!], sizedFields: [String!], requireOneSlicingArgument: Boolean = true)",
            locations: "FIELD_DEFINITION",
            repeatable: false,
            min_version: "v2.9",
        });
    }

    directives
}

/// Check if version is greater than or equal to min_version
fn version_gte(version: &str, min_version: &str) -> bool {
    // Simple version comparison: v2.3 >= v2.1
    let parse_version = |v: &str| -> (u32, u32) {
        let v = v.strip_prefix('v').unwrap_or(v);
        let parts: Vec<&str> = v.split('.').collect();
        let major = parts.first().and_then(|s| s.parse().ok()).unwrap_or(0);
        let minor = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        (major, minor)
    };

    let (v_major, v_minor) = parse_version(version);
    let (min_major, min_minor) = parse_version(min_version);

    v_major > min_major || (v_major == min_major && v_minor >= min_minor)
}

/// Check if a version is known/supported
pub fn is_known_version(version: &Option<String>) -> bool {
    match version {
        None => false,
        Some(v) => {
            // Support v2.0 through v2.9
            version_gte(v, "v2.0") && !version_gte(v, "v3.0")
        }
    }
}

/// Generate the SDL prelude for all @link directives.
///
/// `user_directives` is the set of directive names that the user's schema already
/// explicitly defines.  Any directive in that set will be skipped in the generated
/// prelude so that we don't emit a duplicate definition — which the GraphQL spec
/// allows (an explicit declaration overrides the `@link`-imported one).
pub fn generate_prelude(links: &[LinkDirective], user_directives: &HashSet<String>) -> String {
    let mut prelude = String::new();

    // Find the link spec and federation spec
    let link_spec = links.iter().find(|l| l.spec.identity == SpecIdentity::Link);
    let fed_spec = links
        .iter()
        .find(|l| l.spec.identity == SpecIdentity::Federation);

    // Always inject @link directive definition if we're in federation mode
    // (even if no explicit @link to the link spec is present)
    if link_spec.is_some() || fed_spec.is_some() {
        prelude.push_str(&generate_link_spec_prelude(link_spec, user_directives));
    }

    // Generate federation prelude if present
    if let Some(fed_link) = fed_spec {
        prelude.push_str(&generate_federation_prelude(fed_link, user_directives));
    }

    prelude
}

/// Generate the prelude for the @link spec itself
fn generate_link_spec_prelude(
    link_spec: Option<&LinkDirective>,
    user_directives: &HashSet<String>,
) -> String {
    let mut prelude = String::new();

    // The @link directive is always named "@link" (it's self-defining)
    let directive_name = "link";

    // Determine type names
    let import_scalar = if let Some(link) = link_spec {
        resolve_type_name("link__Import", &link.imports, &link.prefix)
    } else {
        "link__Import".to_string()
    };

    let purpose_enum = if let Some(link) = link_spec {
        resolve_type_name("link__Purpose", &link.imports, &link.prefix)
    } else {
        "link__Purpose".to_string()
    };

    prelude.push_str(&format!("scalar {import_scalar}\n"));
    prelude.push_str(&format!("enum {purpose_enum} {{ SECURITY EXECUTION }}\n"));

    // Only emit the @link directive definition if the user hasn't already declared it
    if !user_directives.contains(directive_name) {
        prelude.push_str(&format!(
            "directive @{directive_name}(url: String!, as: String, for: {purpose_enum}, import: [{import_scalar}]) repeatable on SCHEMA\n\n",
        ));
    }

    prelude
}

/// Generate the prelude for federation directives
fn generate_federation_prelude(
    fed_link: &LinkDirective,
    user_directives: &HashSet<String>,
) -> String {
    let mut prelude = String::new();
    let version = fed_link.spec.version.as_deref().unwrap_or("v2.0");

    // Build a map of imported names for quick lookup
    let import_map: HashMap<String, String> = fed_link
        .imports
        .iter()
        .filter(|i| i.is_directive)
        .map(|i| (i.original_name.clone(), i.local_name.clone()))
        .collect();

    let type_import_map: HashMap<String, String> = fed_link
        .imports
        .iter()
        .filter(|i| !i.is_directive)
        .map(|i| (i.original_name.clone(), i.local_name.clone()))
        .collect();

    // Generate supporting scalars
    let fieldset_name = resolve_type_name_from_map("FieldSet", &type_import_map, &fed_link.prefix);
    prelude.push_str(&format!("scalar {fieldset_name}\n"));

    if version_gte(version, "v2.5") {
        let scope_name =
            resolve_type_name_from_map("federation__Scope", &type_import_map, &fed_link.prefix);
        prelude.push_str(&format!("scalar {scope_name}\n"));
    }

    if version_gte(version, "v2.6") {
        let policy_name =
            resolve_type_name_from_map("federation__Policy", &type_import_map, &fed_link.prefix);
        prelude.push_str(&format!("scalar {policy_name}\n"));
    }

    if version_gte(version, "v2.8") {
        let context_name =
            resolve_type_name_from_map("ContextFieldValue", &type_import_map, &fed_link.prefix);
        prelude.push_str(&format!("scalar {context_name}\n"));
    }

    prelude.push('\n');

    // Generate directives
    let directives = get_federation_directives(version);
    for directive in directives {
        let directive_name = if import_map.contains_key(directive.name) {
            // Imported - use local name
            import_map[directive.name].clone()
        } else {
            // Not imported - use namespaced name
            format!("{}__{}", fed_link.prefix, directive.name)
        };

        // Skip directives that the user has already explicitly defined in their schema.
        // Per the GraphQL spec, an explicit declaration overrides the @link-imported one,
        // allowing schemas to support engines that don't handle @link imports correctly.
        if user_directives.contains(&directive_name) {
            continue;
        }

        // Resolve type references in arguments
        let mut arguments = directive.arguments.to_string();
        arguments = arguments.replace("FieldSet", &fieldset_name);
        if version_gte(version, "v2.5") {
            let scope_name =
                resolve_type_name_from_map("federation__Scope", &type_import_map, &fed_link.prefix);
            arguments = arguments.replace("federation__Scope", &scope_name);
        }
        if version_gte(version, "v2.6") {
            let policy_name = resolve_type_name_from_map(
                "federation__Policy",
                &type_import_map,
                &fed_link.prefix,
            );
            arguments = arguments.replace("federation__Policy", &policy_name);
        }
        if version_gte(version, "v2.8") {
            let context_name =
                resolve_type_name_from_map("ContextFieldValue", &type_import_map, &fed_link.prefix);
            arguments = arguments.replace("ContextFieldValue", &context_name);
        }

        let repeatable = if directive.repeatable {
            "repeatable "
        } else {
            ""
        };

        prelude.push_str(&format!(
            "directive @{}{} {}on {}\n",
            directive_name, arguments, repeatable, directive.locations
        ));
    }

    prelude
}

/// Resolve a directive name based on imports and prefix
#[allow(dead_code)]
fn resolve_directive_name(original: &str, imports: &[ImportEntry], prefix: &str) -> String {
    imports
        .iter()
        .find(|i| i.is_directive && i.original_name == original)
        .map(|i| i.local_name.clone())
        .unwrap_or_else(|| format!("{prefix}__{original}"))
}

/// Resolve a type name based on imports and prefix
fn resolve_type_name(original: &str, imports: &[ImportEntry], _prefix: &str) -> String {
    imports
        .iter()
        .find(|i| !i.is_directive && i.original_name == original)
        .map(|i| i.local_name.clone())
        .unwrap_or_else(|| original.to_string())
}

/// Resolve a type name from a pre-built import map
fn resolve_type_name_from_map(
    original: &str,
    type_import_map: &HashMap<String, String>,
    _prefix: &str,
) -> String {
    type_import_map
        .get(original)
        .cloned()
        .unwrap_or_else(|| original.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use apollo_compiler::Name;

    #[test]
    fn test_parse_link_url_federation_v2_0() {
        let spec = parse_link_url("https://specs.apollo.dev/federation/v2.0");
        assert_eq!(spec.name, Some("federation".to_string()));
        assert_eq!(spec.version, Some("v2.0".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Federation);
    }

    #[test]
    fn test_parse_link_url_federation_v2_3() {
        let spec = parse_link_url("https://specs.apollo.dev/federation/v2.3");
        assert_eq!(spec.name, Some("federation".to_string()));
        assert_eq!(spec.version, Some("v2.3".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Federation);
    }

    #[test]
    fn test_parse_link_url_link_v1_0() {
        let spec = parse_link_url("https://specs.apollo.dev/link/v1.0");
        assert_eq!(spec.name, Some("link".to_string()));
        assert_eq!(spec.version, Some("v1.0".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Link);
    }

    #[test]
    fn test_parse_link_url_unknown() {
        let spec = parse_link_url("https://example.com/custom/v1.0");
        assert_eq!(spec.name, Some("custom".to_string()));
        assert_eq!(spec.version, Some("v1.0".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Unknown);
    }

    #[test]
    fn test_parse_link_url_trailing_slash() {
        let spec = parse_link_url("https://specs.apollo.dev/federation/v2.0/");
        assert_eq!(spec.name, Some("federation".to_string()));
        assert_eq!(spec.version, Some("v2.0".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Federation);
    }

    #[test]
    fn test_parse_link_url_with_query_string() {
        let spec = parse_link_url("https://specs.apollo.dev/federation/v2.0?foo=bar");
        assert_eq!(spec.name, Some("federation".to_string()));
        assert_eq!(spec.version, Some("v2.0".to_string()));
        assert_eq!(spec.identity, SpecIdentity::Federation);
    }

    #[test]
    fn test_parse_link_url_no_version() {
        let spec = parse_link_url("https://specs.apollo.dev/federation");
        assert_eq!(spec.name, Some("federation".to_string()));
        assert_eq!(spec.version, None);
        assert_eq!(spec.identity, SpecIdentity::Federation);
    }

    #[test]
    fn test_parse_link_url_too_short() {
        let spec = parse_link_url("https://example.com");
        assert_eq!(spec.name, None);
        assert_eq!(spec.version, None);
        assert_eq!(spec.identity, SpecIdentity::Unknown);
    }

    #[test]
    fn test_parse_import_item_string_directive() {
        let value = Node::new(Value::String("@key".to_string()));
        let entry = parse_import_item(&value).unwrap();
        assert_eq!(entry.original_name, "key");
        assert_eq!(entry.local_name, "key");
        assert!(entry.is_directive);
    }

    #[test]
    fn test_parse_import_item_string_type() {
        let value = Node::new(Value::String("FieldSet".to_string()));
        let entry = parse_import_item(&value).unwrap();
        assert_eq!(entry.original_name, "FieldSet");
        assert_eq!(entry.local_name, "FieldSet");
        assert!(!entry.is_directive);
    }

    #[test]
    fn test_parse_import_item_object_with_rename() {
        let mut obj = vec![];
        obj.push((
            Name::new("name").unwrap(),
            Node::new(Value::String("@key".to_string())),
        ));
        obj.push((
            Name::new("as").unwrap(),
            Node::new(Value::String("@primaryKey".to_string())),
        ));
        let value = Node::new(Value::Object(obj));
        let entry = parse_import_item(&value).unwrap();
        assert_eq!(entry.original_name, "key");
        assert_eq!(entry.local_name, "primaryKey");
        assert!(entry.is_directive);
    }

    #[test]
    fn test_parse_import_item_object_type_rename() {
        let mut obj = vec![];
        obj.push((
            Name::new("name").unwrap(),
            Node::new(Value::String("FieldSet".to_string())),
        ));
        obj.push((
            Name::new("as").unwrap(),
            Node::new(Value::String("MyFieldSet".to_string())),
        ));
        let value = Node::new(Value::Object(obj));
        let entry = parse_import_item(&value).unwrap();
        assert_eq!(entry.original_name, "FieldSet");
        assert_eq!(entry.local_name, "MyFieldSet");
        assert!(!entry.is_directive);
    }

    #[test]
    fn test_version_gte() {
        assert!(version_gte("v2.3", "v2.0"));
        assert!(version_gte("v2.3", "v2.3"));
        assert!(!version_gte("v2.0", "v2.3"));
        assert!(version_gte("v3.0", "v2.9"));
        assert!(!version_gte("v1.0", "v2.0"));
    }

    #[test]
    fn test_is_known_version() {
        assert!(is_known_version(&Some("v2.0".to_string())));
        assert!(is_known_version(&Some("v2.3".to_string())));
        assert!(is_known_version(&Some("v2.9".to_string())));
        assert!(!is_known_version(&Some("v3.0".to_string())));
        assert!(!is_known_version(&Some("v1.0".to_string())));
        assert!(!is_known_version(&None));
    }

    #[test]
    fn test_get_federation_directives_v2_0() {
        let directives = get_federation_directives("v2.0");
        let names: Vec<&str> = directives.iter().map(|d| d.name).collect();
        assert!(names.contains(&"key"));
        assert!(names.contains(&"requires"));
        assert!(names.contains(&"provides"));
        assert!(names.contains(&"external"));
        assert!(names.contains(&"shareable"));
        assert!(names.contains(&"override"));
        assert!(!names.contains(&"composeDirective")); // v2.1+
        assert!(!names.contains(&"interfaceObject")); // v2.3+
    }

    #[test]
    fn test_get_federation_directives_v2_3() {
        let directives = get_federation_directives("v2.3");
        let names: Vec<&str> = directives.iter().map(|d| d.name).collect();
        assert!(names.contains(&"composeDirective")); // v2.1+
        assert!(names.contains(&"interfaceObject")); // v2.3+
        assert!(!names.contains(&"authenticated")); // v2.5+
    }

    #[test]
    fn test_get_federation_directives_v2_5() {
        let directives = get_federation_directives("v2.5");
        let names: Vec<&str> = directives.iter().map(|d| d.name).collect();
        assert!(names.contains(&"authenticated"));
        assert!(names.contains(&"requiresScopes"));
        assert!(!names.contains(&"policy")); // v2.6+
    }

    #[test]
    fn test_shareable_repeatable_v2_2() {
        let directives_v2_0 = get_federation_directives("v2.0");
        let shareable_v2_0 = directives_v2_0
            .iter()
            .find(|d| d.name == "shareable")
            .unwrap();
        assert!(!shareable_v2_0.repeatable);

        let directives_v2_2 = get_federation_directives("v2.2");
        let shareable_v2_2 = directives_v2_2
            .iter()
            .find(|d| d.name == "shareable")
            .unwrap();
        assert!(shareable_v2_2.repeatable);
    }

    #[test]
    fn test_override_arguments_v2_7() {
        let directives_v2_0 = get_federation_directives("v2.0");
        let override_v2_0 = directives_v2_0
            .iter()
            .find(|d| d.name == "override")
            .unwrap();
        assert_eq!(override_v2_0.arguments, "(from: String!)");

        let directives_v2_7 = get_federation_directives("v2.7");
        let override_v2_7 = directives_v2_7
            .iter()
            .find(|d| d.name == "override")
            .unwrap();
        assert_eq!(override_v2_7.arguments, "(from: String!, label: String)");
    }

    #[test]
    fn test_resolve_directive_name_imported() {
        let imports = vec![ImportEntry {
            original_name: "key".to_string(),
            local_name: "key".to_string(),
            is_directive: true,
        }];
        let name = resolve_directive_name("key", &imports, "federation");
        assert_eq!(name, "key");
    }

    #[test]
    fn test_resolve_directive_name_not_imported() {
        let imports = vec![ImportEntry {
            original_name: "key".to_string(),
            local_name: "key".to_string(),
            is_directive: true,
        }];
        let name = resolve_directive_name("requires", &imports, "federation");
        assert_eq!(name, "federation__requires");
    }

    #[test]
    fn test_resolve_directive_name_custom_prefix() {
        let imports = vec![];
        let name = resolve_directive_name("key", &imports, "fed");
        assert_eq!(name, "fed__key");
    }

    #[test]
    fn test_resolve_directive_name_renamed() {
        let imports = vec![ImportEntry {
            original_name: "key".to_string(),
            local_name: "primaryKey".to_string(),
            is_directive: true,
        }];
        let name = resolve_directive_name("key", &imports, "federation");
        assert_eq!(name, "primaryKey");
    }

    #[test]
    fn test_generate_link_spec_prelude_default() {
        let prelude = generate_link_spec_prelude(None, &HashSet::new());
        assert!(prelude.contains("scalar link__Import"));
        assert!(prelude.contains("enum link__Purpose { SECURITY EXECUTION }"));
        assert!(prelude.contains("directive @link(url: String!"));
    }

    #[test]
    fn test_extract_link_directives_from_schema() {
        let schema = r#"
            schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"]) {
                query: Query
            }
            type Query { field: String }
        "#;
        let document = apollo_compiler::ast::Document::parse(schema, "test.graphql").unwrap();
        let links = extract_link_directives(&document);
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].url, "https://specs.apollo.dev/federation/v2.0");
        assert_eq!(links[0].spec.identity, SpecIdentity::Federation);
        assert_eq!(links[0].imports.len(), 1);
        assert_eq!(links[0].imports[0].original_name, "key");
    }

    #[test]
    fn test_extract_link_directives_with_rename() {
        let schema = r#"
            schema @link(
                url: "https://specs.apollo.dev/federation/v2.3",
                import: [{name: "@key", as: "@primaryKey"}],
                as: "fed"
            ) {
                query: Query
            }
            type Query { field: String }
        "#;
        let document = apollo_compiler::ast::Document::parse(schema, "test.graphql").unwrap();
        let links = extract_link_directives(&document);
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].prefix, "fed");
        assert_eq!(links[0].imports.len(), 1);
        assert_eq!(links[0].imports[0].original_name, "key");
        assert_eq!(links[0].imports[0].local_name, "primaryKey");
    }

    #[test]
    fn test_generate_federation_prelude_basic() {
        let link = LinkDirective {
            url: "https://specs.apollo.dev/federation/v2.0".to_string(),
            spec: LinkSpec {
                name: Some("federation".to_string()),
                version: Some("v2.0".to_string()),
                identity: SpecIdentity::Federation,
            },
            prefix: "federation".to_string(),
            imports: vec![ImportEntry {
                original_name: "key".to_string(),
                local_name: "key".to_string(),
                is_directive: true,
            }],
        };

        let prelude = generate_federation_prelude(&link, &HashSet::new());
        assert!(prelude.contains("scalar FieldSet"));
        assert!(prelude.contains("directive @key(fields: FieldSet!"));
        assert!(prelude.contains("directive @federation__requires"));
        assert!(prelude.contains("directive @federation__provides"));
    }

    #[test]
    fn test_generate_federation_prelude_custom_prefix() {
        let link = LinkDirective {
            url: "https://specs.apollo.dev/federation/v2.0".to_string(),
            spec: LinkSpec {
                name: Some("federation".to_string()),
                version: Some("v2.0".to_string()),
                identity: SpecIdentity::Federation,
            },
            prefix: "fed".to_string(),
            imports: vec![ImportEntry {
                original_name: "key".to_string(),
                local_name: "key".to_string(),
                is_directive: true,
            }],
        };

        let prelude = generate_federation_prelude(&link, &HashSet::new());
        assert!(prelude.contains("directive @key(fields: FieldSet!"));
        assert!(prelude.contains("directive @fed__requires"));
        assert!(prelude.contains("directive @fed__provides"));
    }

    #[test]
    fn test_generate_federation_prelude_all_namespaced() {
        let link = LinkDirective {
            url: "https://specs.apollo.dev/federation/v2.0".to_string(),
            spec: LinkSpec {
                name: Some("federation".to_string()),
                version: Some("v2.0".to_string()),
                identity: SpecIdentity::Federation,
            },
            prefix: "federation".to_string(),
            imports: vec![],
        };

        let prelude = generate_federation_prelude(&link, &HashSet::new());
        assert!(prelude.contains("directive @federation__key"));
        assert!(prelude.contains("directive @federation__requires"));
        assert!(prelude.contains("directive @federation__provides"));
    }

    #[test]
    fn test_generate_prelude_combined() {
        let link = LinkDirective {
            url: "https://specs.apollo.dev/link/v1.0".to_string(),
            spec: LinkSpec {
                name: Some("link".to_string()),
                version: Some("v1.0".to_string()),
                identity: SpecIdentity::Link,
            },
            prefix: "link".to_string(),
            imports: vec![],
        };

        let fed = LinkDirective {
            url: "https://specs.apollo.dev/federation/v2.0".to_string(),
            spec: LinkSpec {
                name: Some("federation".to_string()),
                version: Some("v2.0".to_string()),
                identity: SpecIdentity::Federation,
            },
            prefix: "federation".to_string(),
            imports: vec![ImportEntry {
                original_name: "key".to_string(),
                local_name: "key".to_string(),
                is_directive: true,
            }],
        };

        let prelude = generate_prelude(&[link, fed], &HashSet::new());
        assert!(prelude.contains("scalar link__Import"));
        assert!(prelude.contains("directive @link(url: String!"));
        assert!(prelude.contains("scalar FieldSet"));
        assert!(prelude.contains("directive @key(fields: FieldSet!"));
    }
}
