# yaml-schema

A library for validating YAML documents against a schema.

## Overview

`yaml-schema` is a schema validation library that allows you to enforce type safety and structural constraints on YAML files. It works directly with an AST (which can be obtained from Psych) representation to provide strict validation without implicit type coercion.

## Usage

### Basic Validation

```ruby
require "yaml-schema"

schema = {
  "type" => "object",
  "properties" => {
    "name" => { "type" => "string" },
    "age" => { "type" => "integer" },
    "active" => { "type" => "boolean" }
  }
}

yaml_string = <<~YAML
  name: "John Doe"
  age: 30
  active: true
YAML

node = Psych.parse(yaml_string)
YAMLSchema::Validator.validate(schema, node.children.first)
```

### Supported Types

- **string** - Scalar string values
- **integer** - Numeric integers
- **boolean** - Boolean values (true/false)
- **null** - Null values
- **array** - Sequences with optional constraints
  - `items` - Schema for all array elements
  - `prefixItems` - Fixed-position tuple validation
  - `maxItems` - Maximum array length
- **object** - Mappings with properties
  - `properties` - Named properties with schemas
  - `items` - Schema for arbitrary key-value pairs
  - `tag` - Optional YAML tag requirement

### Type Unions

Specify multiple valid types for a field:

```ruby
schema = {
  "type" => "object",
  "properties" => {
    "value" => { "type" => ["null", "string"] }
  }
}
```

### Nested Objects and Arrays

```ruby
schema = {
  "type" => "object",
  "properties" => {
    "users" => {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "tags" => {
            "type" => "array",
            "items" => { "type" => "string" }
          }
        }
      }
    }
  }
}
```

### Compiled Validators

If you validate many documents against the same schema, you can compile the
schema into a validator class specialized for it, rather than interpreting
the schema on every call:

```ruby
PersonValidator = YAMLSchema::Compiler.compile(schema)

PersonValidator.validate(node)          # raises on error, returns true otherwise
PersonValidator.invalid?(node)          # returns the error, or false
PersonValidator.validate(node, aliases: false)
PersonValidator.new(node_info).validate(node)
```

Compiled validators raise the same exceptions with the same messages as
`YAMLSchema::Validator`. The schema itself is validated at compile time.

You can also generate Ruby source and check it into your project:

```ruby
File.write "person_validator.rb",
  YAMLSchema::Compiler.to_ruby(schema, class_name: "PersonValidator")
```

## Error Handling

Validation errors include detailed path information:

```ruby
begin
  YAMLSchema::Validator.validate(schema, node)
rescue YAMLSchema::Validator::UnexpectedType => e
  puts e.message  # e.g., "Expected integer at root -> age"
end
```

### Error Types

- `UnexpectedType` - Node doesn't match expected type
- `UnexpectedProperty` - Object has unexpected properties
- `UnexpectedTag` - YAML tag doesn't match schema
- `UnexpectedValue` - Value doesn't match constraints
- `InvalidSchema` - Schema definition is invalid
