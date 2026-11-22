//! Reads the JSON Schema that schemars emits into a small type model the GDScript renderer walks.

use std::collections::BTreeMap;

use serde_json::{Map, Value};

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum ModelError {
    #[error("the schema has no `$defs` object")]
    MissingDefinitions,
    #[error("unsupported schema at {path}: {reason}")]
    Unsupported { path: String, reason: &'static str },
    #[error("unknown reference {reference} at {path}")]
    UnknownReference { path: String, reference: String },
}

#[derive(Debug, Clone, PartialEq)]
pub enum TypeRef {
    Integer,
    Number,
    Boolean,
    String,
    /// A `$defs` entry by name.
    Named(String),
    Array(Box<TypeRef>),
    Tuple(Vec<TypeRef>),
    Nullable(Box<TypeRef>),
    /// Anything the model cannot type; passed through unchanged.
    Any,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Field {
    pub name: String,
    pub type_ref: TypeRef,
    pub required: bool,
    pub description: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum VariantShape {
    /// `{"<tag>": "Name", ...fields}`, serde's internally tagged enums.
    Tagged { fields: Vec<Field> },
    /// `"Name"`, a unit variant of an externally tagged enum.
    UnitString,
    /// `{"Name": value}`, a newtype variant of an externally tagged enum.
    ExternalNewtype { value: TypeRef },
    /// `{"Name": {...fields}}`, a struct variant of an externally tagged enum.
    ExternalStruct { fields: Vec<Field> },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Variant {
    pub name: String,
    pub description: Option<String>,
    pub shape: VariantShape,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Definition {
    Struct {
        fields: Vec<Field>,
    },
    /// Plain string enum: unit variants without a tag object.
    StringEnum {
        values: Vec<String>,
    },
    /// Internally tagged enum whose variants are all units: `{"code": "NotYourTurn"}`.
    TagEnum {
        tag: String,
        values: Vec<String>,
    },
    Union {
        /// The tag property when any variant is internally tagged.
        tag: Option<String>,
        variants: Vec<Variant>,
    },
    /// A named primitive, array or tuple, such as `TileId(u8)` or `ResourceCounts([u8; 5])`.
    Alias {
        target: TypeRef,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct NamedDefinition {
    pub description: Option<String>,
    pub definition: Definition,
}

/// Every `$defs` entry by name; a `BTreeMap` keeps the output order stable.
#[derive(Debug, Clone, PartialEq)]
pub struct Model {
    pub definitions: BTreeMap<String, NamedDefinition>,
}

impl Model {
    pub fn from_schema(schema: &Value) -> Result<Model, ModelError> {
        let definitions = schema
            .get("$defs")
            .and_then(Value::as_object)
            .ok_or(ModelError::MissingDefinitions)?;
        let mut model = Model {
            definitions: BTreeMap::new(),
        };
        for (name, node) in definitions {
            let path = format!("#/$defs/{name}");
            let definition = read_definition(node, definitions, &path)?;
            model.definitions.insert(
                name.clone(),
                NamedDefinition {
                    description: description(node),
                    definition,
                },
            );
        }
        model.check_references()?;
        Ok(model)
    }

    pub fn get(&self, name: &str) -> Option<&Definition> {
        self.definitions.get(name).map(|named| &named.definition)
    }

    /// Follows aliases so `TileId` reads as `Integer`.
    pub fn resolve<'model>(&'model self, type_ref: &'model TypeRef) -> &'model TypeRef {
        let TypeRef::Named(name) = type_ref else {
            return type_ref;
        };
        match self.get(name) {
            Some(Definition::Alias { target }) => self.resolve(target),
            _ => type_ref,
        }
    }

    fn check_references(&self) -> Result<(), ModelError> {
        for (name, named) in &self.definitions {
            for type_ref in referenced_types(&named.definition) {
                self.check_reference(type_ref, name)?;
            }
        }
        Ok(())
    }

    fn check_reference(&self, type_ref: &TypeRef, owner: &str) -> Result<(), ModelError> {
        match type_ref {
            TypeRef::Named(name) if !self.definitions.contains_key(name) => {
                Err(ModelError::UnknownReference {
                    path: format!("#/$defs/{owner}"),
                    reference: name.clone(),
                })
            }
            TypeRef::Array(item) | TypeRef::Nullable(item) => self.check_reference(item, owner),
            TypeRef::Tuple(items) => items
                .iter()
                .try_for_each(|item| self.check_reference(item, owner)),
            _ => Ok(()),
        }
    }
}

fn referenced_types(definition: &Definition) -> Vec<&TypeRef> {
    match definition {
        Definition::Struct { fields } => fields.iter().map(|field| &field.type_ref).collect(),
        Definition::Alias { target } => vec![target],
        Definition::Union { variants, .. } => variants
            .iter()
            .flat_map(|variant| match &variant.shape {
                VariantShape::Tagged { fields } | VariantShape::ExternalStruct { fields } => {
                    fields.iter().map(|field| &field.type_ref).collect()
                }
                VariantShape::ExternalNewtype { value } => vec![value],
                VariantShape::UnitString => Vec::new(),
            })
            .collect(),
        Definition::StringEnum { .. } | Definition::TagEnum { .. } => Vec::new(),
    }
}

fn description(node: &Value) -> Option<String> {
    node.get("description")
        .and_then(Value::as_str)
        .map(str::to_string)
}

fn unsupported(path: &str, reason: &'static str) -> ModelError {
    ModelError::Unsupported {
        path: path.to_string(),
        reason,
    }
}

fn read_definition(
    node: &Value,
    definitions: &Map<String, Value>,
    path: &str,
) -> Result<Definition, ModelError> {
    if let Some(alternatives) = alternatives(node) {
        return read_alternatives(alternatives, definitions, path);
    }
    if let Some(values) = string_enum_values(node) {
        return Ok(Definition::StringEnum { values });
    }
    if node.get("properties").is_some() {
        let fields = read_fields(node, definitions, path)?;
        return Ok(Definition::Struct { fields });
    }
    Ok(Definition::Alias {
        target: read_type(node, path)?,
    })
}

fn alternatives(node: &Value) -> Option<&Vec<Value>> {
    node.get("oneOf")
        .or_else(|| node.get("anyOf"))
        .and_then(Value::as_array)
}

fn string_enum_values(node: &Value) -> Option<Vec<String>> {
    if let Some(constant) = node.get("const").and_then(Value::as_str) {
        return Some(vec![constant.to_string()]);
    }
    let values = node.get("enum")?.as_array()?;
    values
        .iter()
        .map(|value| value.as_str().map(str::to_string))
        .collect()
}

fn read_alternatives(
    alternatives: &[Value],
    definitions: &Map<String, Value>,
    path: &str,
) -> Result<Definition, ModelError> {
    let non_null: Vec<&Value> = alternatives
        .iter()
        .filter(|alternative| !is_null_schema(alternative))
        .collect();
    if non_null.len() < alternatives.len() {
        return Err(unsupported(
            path,
            "a named definition that is itself nullable",
        ));
    }
    let tag = common_tag(&non_null);
    let mut variants = Vec::new();
    for (index, alternative) in non_null.iter().enumerate() {
        let variant_path = format!("{path}/oneOf/{index}");
        let mut read = read_variant(alternative, tag.as_deref(), definitions, &variant_path)?;
        variants.append(&mut read);
    }
    Ok(classify_union(tag, variants))
}

/// Unions of only unit variants become string or tag enums, which read better in GDScript.
fn classify_union(tag: Option<String>, variants: Vec<Variant>) -> Definition {
    let names = variants
        .iter()
        .map(|variant| variant.name.clone())
        .collect();
    let all_unit_strings = variants
        .iter()
        .all(|variant| variant.shape == VariantShape::UnitString);
    if all_unit_strings {
        return Definition::StringEnum { values: names };
    }
    let all_bare_tags = variants.iter().all(
        |variant| matches!(&variant.shape, VariantShape::Tagged { fields } if fields.is_empty()),
    );
    match tag {
        Some(tag) if all_bare_tags => Definition::TagEnum { tag, values: names },
        tag => Definition::Union { tag, variants },
    }
}

fn is_null_schema(node: &Value) -> bool {
    node.get("type").and_then(Value::as_str) == Some("null")
}

/// The required property holding a string constant in every tagged alternative.
fn common_tag(alternatives: &[&Value]) -> Option<String> {
    alternatives
        .iter()
        .find_map(|alternative| tag_property(alternative))
}

fn tag_property(node: &Value) -> Option<String> {
    let properties = node.get("properties")?.as_object()?;
    let required = node.get("required")?.as_array()?;
    properties.iter().find_map(|(name, property)| {
        let constant = property.get("const")?.as_str();
        let is_required = required.iter().any(|entry| entry.as_str() == Some(name));
        (constant.is_some() && is_required).then(|| name.clone())
    })
}

fn read_variant(
    node: &Value,
    tag: Option<&str>,
    definitions: &Map<String, Value>,
    path: &str,
) -> Result<Vec<Variant>, ModelError> {
    let description = description(node);
    if let Some(values) = string_enum_values(node) {
        let variants = values
            .into_iter()
            .map(|name| Variant {
                name,
                description: description.clone(),
                shape: VariantShape::UnitString,
            })
            .collect();
        return Ok(variants);
    }
    if let Some(tag) = tag.filter(|tag| tag_property(node).as_deref() == Some(*tag)) {
        let name = node["properties"][tag]["const"]
            .as_str()
            .ok_or_else(|| unsupported(path, "the tag is not a string constant"))?
            .to_string();
        let fields = read_fields(node, definitions, path)?
            .into_iter()
            .filter(|field| field.name != tag)
            .collect();
        let shape = VariantShape::Tagged { fields };
        return Ok(vec![Variant {
            name,
            description,
            shape,
        }]);
    }
    read_external_variant(node, description, definitions, path).map(|variant| vec![variant])
}

fn read_external_variant(
    node: &Value,
    description: Option<String>,
    definitions: &Map<String, Value>,
    path: &str,
) -> Result<Variant, ModelError> {
    let properties = node
        .get("properties")
        .and_then(Value::as_object)
        .filter(|properties| properties.len() == 1)
        .ok_or_else(|| unsupported(path, "a variant that is neither tagged nor external"))?;
    let (name, value) = properties
        .iter()
        .next()
        .ok_or_else(|| unsupported(path, "an external variant without a key"))?;
    let value_path = format!("{path}/properties/{name}");
    let shape = if value.get("properties").is_some() {
        VariantShape::ExternalStruct {
            fields: read_fields(value, definitions, &value_path)?,
        }
    } else {
        VariantShape::ExternalNewtype {
            value: read_type(value, &value_path)?,
        }
    };
    Ok(Variant {
        name: name.clone(),
        description,
        shape,
    })
}

/// Fields of an object schema, required ones in declaration order first, then the rest sorted.
fn read_fields(
    node: &Value,
    definitions: &Map<String, Value>,
    path: &str,
) -> Result<Vec<Field>, ModelError> {
    let mut properties = node
        .get("properties")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut required: Vec<String> = string_list(node.get("required"));
    // Internally tagged newtype variants reference the inner struct next to the tag.
    for inner in referenced_objects(node, definitions, path)? {
        properties.extend(
            inner
                .get("properties")
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default(),
        );
        required.extend(string_list(inner.get("required")));
    }
    let mut names: Vec<&String> = required
        .iter()
        .filter(|name| properties.contains_key(*name))
        .collect();
    let mut optional: Vec<&String> = properties
        .keys()
        .filter(|name| !required.contains(name))
        .collect();
    optional.sort();
    names.dedup();
    names.extend(optional);
    names
        .into_iter()
        .map(|name| {
            let property = &properties[name];
            Ok(Field {
                name: name.clone(),
                type_ref: read_type(property, &format!("{path}/properties/{name}"))?,
                required: required.contains(name),
                description: description(property),
            })
        })
        .collect()
}

fn string_list(node: Option<&Value>) -> Vec<String> {
    node.and_then(Value::as_array)
        .map(|entries| {
            entries
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn referenced_objects<'schema>(
    node: &'schema Value,
    definitions: &'schema Map<String, Value>,
    path: &str,
) -> Result<Vec<&'schema Value>, ModelError> {
    let mut references: Vec<&Value> = node.get("$ref").into_iter().collect();
    if let Some(parts) = node.get("allOf").and_then(Value::as_array) {
        references.extend(parts.iter().filter_map(|part| part.get("$ref")));
    }
    references
        .into_iter()
        .map(|reference| {
            let name = reference_name(reference, path)?;
            definitions
                .get(&name)
                .ok_or_else(|| ModelError::UnknownReference {
                    path: path.to_string(),
                    reference: name,
                })
        })
        .collect()
}

fn reference_name(reference: &Value, path: &str) -> Result<String, ModelError> {
    let text = reference
        .as_str()
        .ok_or_else(|| unsupported(path, "a `$ref` that is not a string"))?;
    text.strip_prefix("#/$defs/")
        .map(str::to_string)
        .ok_or_else(|| unsupported(path, "a `$ref` outside `#/$defs/`"))
}

/// The type of a property or array item.
pub fn read_type(node: &Value, path: &str) -> Result<TypeRef, ModelError> {
    if let Some(reference) = node.get("$ref") {
        return Ok(TypeRef::Named(reference_name(reference, path)?));
    }
    if let Some(alternatives) = alternatives(node) {
        return read_type_alternatives(alternatives, path);
    }
    if let Some(parts) = node.get("allOf").and_then(Value::as_array) {
        return match parts.as_slice() {
            [single] => read_type(single, path),
            _ => Ok(TypeRef::Any),
        };
    }
    match node.get("type") {
        Some(Value::String(name)) => read_named_type(node, name, path),
        Some(Value::Array(names)) => read_type_list(node, names, path),
        _ => Ok(TypeRef::Any),
    }
}

fn read_type_alternatives(alternatives: &[Value], path: &str) -> Result<TypeRef, ModelError> {
    let non_null: Vec<&Value> = alternatives
        .iter()
        .filter(|alternative| !is_null_schema(alternative))
        .collect();
    let inner = match non_null.as_slice() {
        [single] => read_type(single, path)?,
        _ => TypeRef::Any,
    };
    if non_null.len() < alternatives.len() {
        return Ok(TypeRef::Nullable(Box::new(inner)));
    }
    Ok(inner)
}

fn read_type_list(node: &Value, names: &[Value], path: &str) -> Result<TypeRef, ModelError> {
    let non_null: Vec<&str> = names
        .iter()
        .filter_map(Value::as_str)
        .filter(|name| *name != "null")
        .collect();
    let inner = match non_null.as_slice() {
        [single] => read_named_type(node, single, path)?,
        _ => TypeRef::Any,
    };
    if non_null.len() < names.len() {
        return Ok(TypeRef::Nullable(Box::new(inner)));
    }
    Ok(inner)
}

fn read_named_type(node: &Value, name: &str, path: &str) -> Result<TypeRef, ModelError> {
    match name {
        "integer" => Ok(TypeRef::Integer),
        "number" => Ok(TypeRef::Number),
        "boolean" => Ok(TypeRef::Boolean),
        "string" => Ok(TypeRef::String),
        "array" => read_array(node, path),
        _ => Ok(TypeRef::Any),
    }
}

fn read_array(node: &Value, path: &str) -> Result<TypeRef, ModelError> {
    if let Some(items) = node.get("prefixItems").and_then(Value::as_array) {
        let items = items
            .iter()
            .enumerate()
            .map(|(index, item)| read_type(item, &format!("{path}/prefixItems/{index}")))
            .collect::<Result<_, _>>()?;
        return Ok(TypeRef::Tuple(items));
    }
    let item = match node.get("items") {
        Some(items) => read_type(items, &format!("{path}/items"))?,
        None => TypeRef::Any,
    };
    Ok(TypeRef::Array(Box::new(item)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn model(definitions: Value) -> Model {
        Model::from_schema(&json!({ "$defs": definitions })).unwrap()
    }

    #[test]
    fn newtype_ids_and_fixed_arrays_are_aliases_that_resolve_to_primitives() {
        let model = model(json!({
            "TileId": {"type": "integer", "format": "uint8"},
            "ResourceCounts": {"type": "array", "items": {"type": "integer"}, "minItems": 5, "maxItems": 5},
        }));
        let tile = TypeRef::Named("TileId".to_string());

        assert_eq!(model.resolve(&tile), &TypeRef::Integer);
        assert_eq!(
            model.get("ResourceCounts"),
            Some(&Definition::Alias {
                target: TypeRef::Array(Box::new(TypeRef::Integer))
            })
        );
    }

    #[test]
    fn options_tuples_and_required_order_are_read_from_properties() {
        let model = model(json!({
            "Offer": {
                "type": "object",
                "properties": {
                    "answers": {"type": "array", "items": {"type": "array", "prefixItems": [{"type": "integer"}, {"type": "boolean"}]}},
                    "to": {"type": ["integer", "null"]},
                    "seat": {"type": "integer"},
                    "port": {"anyOf": [{"$ref": "#/$defs/Offer"}, {"type": "null"}]},
                },
                "required": ["seat", "answers", "to"],
            },
        }));
        let Some(Definition::Struct { fields }) = model.get("Offer") else {
            panic!("expected a struct");
        };
        let summary: Vec<(&str, &TypeRef, bool)> = fields
            .iter()
            .map(|field| (field.name.as_str(), &field.type_ref, field.required))
            .collect();

        assert_eq!(
            summary,
            vec![
                ("seat", &TypeRef::Integer, true),
                (
                    "answers",
                    &TypeRef::Array(Box::new(TypeRef::Tuple(vec![
                        TypeRef::Integer,
                        TypeRef::Boolean
                    ]))),
                    true
                ),
                ("to", &TypeRef::Nullable(Box::new(TypeRef::Integer)), true),
                (
                    "port",
                    &TypeRef::Nullable(Box::new(TypeRef::Named("Offer".to_string()))),
                    false
                ),
            ]
        );
    }

    #[test]
    fn unions_split_into_tagged_external_and_enum_shapes() {
        let model = model(json!({
            "Port": {"oneOf": [
                {"type": "string", "const": "Generic"},
                {"type": "object", "properties": {"Specific": {"type": "string"}}, "required": ["Specific"], "additionalProperties": false},
            ]},
            "Error": {"oneOf": [
                {"type": "object", "properties": {"code": {"type": "string", "const": "A"}}, "required": ["code"]},
                {"type": "object", "properties": {"code": {"type": "string", "const": "B"}}, "required": ["code"]},
            ]},
            "Message": {"oneOf": [
                {"type": "object", "properties": {"type": {"type": "string", "const": "Hello"}, "name": {"type": "string"}}, "required": ["type", "name"]},
                {"type": "object", "properties": {"type": {"type": "string", "const": "Inner"}}, "$ref": "#/$defs/Inner", "required": ["type"]},
            ]},
            "Inner": {"type": "object", "properties": {"value": {"type": "integer"}}, "required": ["value"]},
            "Resource": {"type": "string", "enum": ["Clay", "Ore"]},
        }));

        assert_eq!(
            model.get("Port"),
            Some(&Definition::Union {
                tag: None,
                variants: vec![
                    Variant {
                        name: "Generic".to_string(),
                        description: None,
                        shape: VariantShape::UnitString
                    },
                    Variant {
                        name: "Specific".to_string(),
                        description: None,
                        shape: VariantShape::ExternalNewtype {
                            value: TypeRef::String
                        }
                    },
                ],
            })
        );
        assert_eq!(
            model.get("Error"),
            Some(&Definition::TagEnum {
                tag: "code".to_string(),
                values: vec!["A".to_string(), "B".to_string()]
            })
        );
        let Some(Definition::Union { tag, variants }) = model.get("Message") else {
            panic!("expected a union");
        };
        assert_eq!(tag.as_deref(), Some("type"));
        let VariantShape::Tagged { fields } = &variants[1].shape else {
            panic!("expected a tagged variant");
        };
        assert_eq!(fields[0].name, "value");
        assert_eq!(
            model.get("Resource"),
            Some(&Definition::StringEnum {
                values: vec!["Clay".to_string(), "Ore".to_string()]
            })
        );
    }

    #[test]
    fn unknown_references_are_rejected() {
        let error = Model::from_schema(&json!({"$defs": {
            "A": {"type": "object", "properties": {"b": {"$ref": "#/$defs/B"}}, "required": ["b"]},
        }}))
        .unwrap_err();

        assert_eq!(
            error,
            ModelError::UnknownReference {
                path: "#/$defs/A".to_string(),
                reference: "B".to_string()
            }
        );
    }
}
