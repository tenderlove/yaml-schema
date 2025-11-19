require "minitest/autorun"
require "yaml-schema"
require "psych"

module YAMLSchema
  class Validator
    class ErrorTest < Minitest::Test
      def test_pattern_symbol
        ast = Psych.parse(Psych.dump({ "foo" => :foo }))

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "symbol",
                "pattern" => /\A:bar\z/
              },
            },
          }, ast.children.first)
        end
      end
      def test_pattern_time
        ast = Psych.parse(Psych.dump({ "foo" => Time.now }))

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "time",
                "pattern" => /\Ayay\z/
              },
            },
          }, ast.children.first)
        end
      end

      def test_pattern_null
        ast = Psych.parse(Psych.dump({ "foo" => nil }))

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "null",
                "pattern" => /\Anotnull\z/
              },
            },
          }, ast.children.first)
        end
      end

      def test_pattern_float
        ast = Psych.parse(Psych.dump({ "foo" => 1.2 }))

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "float",
                "pattern" => /\A1\.3\z/
              },
            },
          }, ast.children.first)
        end
      end

      def test_pattern_boolean
        yaml = "---\n foo: true"
        ast = Psych.parse(yaml)

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "boolean",
                "pattern" => /\Atru\z/
              },
            },
          }, ast.children.first)
        end
      end

      def test_pattern_date
        yaml = "---\n foo: 2025-11-19"

        ast = Psych.parse(yaml)
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => {
              "type" => "date",
              "pattern" => /\A2025-11-19\z/
            },
          },
        }, ast.children.first)

        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "date",
                "pattern" => /\A2025-11-20\z/
              },
            },
          }, ast.children.first)
        end
      end

      def test_accept_non_strings
        [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |v|
          ast = Psych.parse(Psych.dump({ "foo" => v }))
          assert Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => { "type" => "float" },
            },
          }, ast.children.first)
        end

        ast = Psych.parse(Psych.dump({ "foo" => Time.now }))
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => { "type" => "time" },
          },
        }, ast.children.first)

        ast = Psych.parse(Psych.dump({ "foo" => Date.today }))
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => { "type" => "date" },
          },
        }, ast.children.first)

        ast = Psych.parse(Psych.dump({ "foo" => :foo }))
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => { "type" => "symbol" },
          },
        }, ast.children.first)
      end

      def test_reject_non_strings
        [Float::INFINITY, -Float::INFINITY, Float::NAN, Time.now, Date.today, :foo].each do |v|
          ast = Psych.parse(Psych.dump({ "foo" => v }))
          assert_raises UnexpectedValue do
            Validator.validate({
              "type" => "object",
              "properties" => {
                "foo" => { "type" => "string" },
              },
            }, ast.children.first)
          end
        end
      end

      def test_property_max_length
        ast = Psych.parse("---\n  hello: world")
        assert_raises InvalidString do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "hello" => { "type" => "string" },
            },
            "propertyNames" => {
              "maxLength" => 4
            },
            "items" => { "type" => "string" },
          }, ast.children.first)
        end

        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "hello" => { "type" => "string" },
          },
          "maxPropertyLength" => 5,
          "items" => { "type" => "string" },
        }, ast.children.first)
      end

      def test_additional_properties
        ast = Psych.parse("---\n  hello: world\n  foo: bar")
        assert_raises UnexpectedProperty do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "hello" => { "type" => "string" },
            },
            "items" => { "type" => "string" }
          }, ast.children.first)
        end

        ast = Psych.parse("---\n  hello: world\n  foo: bar")
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "hello" => { "type" => "string" },
          },
          "items" => { "type" => "string" },
          "additionalProperties" => {
            "type" => "string"
          },
        }, ast.children.first)

        ast = Psych.parse("---\n  hello: world\n  foo: bar")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "hello" => { "type" => "string" },
            },
            "items" => { "type" => "string" },
            "additionalProperties" => {
              "type" => "null"
            },
          }, ast.children.first)
        end
      end

      def test_string_min_length
        ast = Psych.parse("--- hello")
        assert_raises InvalidString do
          Validator.validate({
            "type" => "string",
            "minLength" => 6,
          }, ast.children.first)
        end

        ast = Psych.parse("--- hello")
        assert Validator.validate({
          "type" => "string",
          "minLength" => 5,
        }, ast.children.first)
      end

      def test_string_max_length
        ast = Psych.parse("--- hello")
        assert_raises InvalidString do
          Validator.validate({
            "type" => "string",
            "maxLength" => 4,
          }, ast.children.first)
        end

        ast = Psych.parse("--- hello")
        assert Validator.validate({
          "type" => "string",
          "maxLength" => 5,
        }, ast.children.first)
      end

      def test_minItems
        ast = Psych.parse("---\n- bar")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "items" => { "type" => "string" },
            "minItems" => 2
          }, ast.children.first)
        end

        ast = Psych.parse("---\n- bar")
        assert Validator.validate({
          "type" => "array",
          "items" => { "type" => "string" },
          "minItems" => 1
        }, ast.children.first)
      end

      def test_regular_expression
        ast = Psych.parse("bar")
        assert_raises InvalidPattern do
          Validator.validate({
            "type" => "string",
            "pattern" => /foo/
          }, ast.children.first)
        end

        assert Validator.validate({
          "type" => "string",
          "pattern" => /bar/
        }, ast.children.first)
      end

      def test_missing_required
        ast = Psych.parse("foo: bar")
        assert_raises MissingRequiredField do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => { "type" => "string" },
              "bar" => { "type" => "string" },
              "baz" => { "type" => "string" },
            },
            "required" => [ "foo", "baz"],
          }, ast.children.first)
        end

        ast = Psych.parse("---\n  foo: bar\n  baz: hello")
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => { "type" => "string" },
            "bar" => { "type" => "string" },
            "baz" => { "type" => "string" },
          },
          "required" => [ "foo", "baz"],
        }, ast.children.first)
      end

      def test_missing_tag
        ast = Psych.parse("foo: bar")
        assert_raises UnexpectedTag do
          Validator.validate({
            "type" => "object",
            "tag" => "aaron"
          }, ast.children.first)
        end
      end

      def test_wrong_tag
        ast = Psych.parse("--- !lolol\nfoo: bar")
        ex = assert_raises UnexpectedTag do
          Validator.validate({
            "type" => "object",
            "tag" => "aaron"
          }, ast.children.first)
        end
        assert_match(/lolol/, ex.message)
      end

      def test_wrong_type
        ast = Psych.parse("foo: bar")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end
        assert_match(/Scalar/, ex.message)

        ast = Psych.parse("foo")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "object",
          }, ast.children.first)
        end
        assert_match(/Mapping/, ex.message)

        ast = Psych.parse("foo")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "array",
          }, ast.children.first)
        end
        assert_match(/Sequence/, ex.message)
      end

      def test_null_error
        ast = Psych.parse("foo")
        ex = assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "null",
          }, ast.children.first)
        end
        assert_match(/empty string/, ex.message)

        ast = Psych.parse("foo: bar")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "null",
          }, ast.children.first)
        end
        assert_match(/Scalar/, ex.message)
      end

      def test_boolean_error
        ast = Psych.parse("foo")
        ex = assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "boolean",
          }, ast.children.first)
        end
        assert_match(/true/, ex.message)

        ast = Psych.parse("foo: bar")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "boolean",
          }, ast.children.first)
        end
        assert_match(/Scalar/, ex.message)
      end

      def test_integer_error
        ast = Psych.parse("foo")
        ex = assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "integer",
          }, ast.children.first)
        end
        assert_match(/expected integer/, ex.message)

        ast = Psych.parse("'foo'")
        ex = assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "integer",
          }, ast.children.first)
        end
        assert_match(/expected integer/, ex.message)

        ast = Psych.parse("foo: bar")
        ex = assert_raises UnexpectedType do
          Validator.validate({
            "type" => "integer",
          }, ast.children.first)
        end
        assert_match(/Scalar/, ex.message)
      end

      def test_error_in_array_sequence
        ast = Psych.parse("- foo\n- 1")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "items" => { "type" => "integer" }
          }, ast.children.first)
        end

        ast = Psych.parse("- 1\n- foo")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "items" => { "type" => "integer" }
          }, ast.children.first)
        end
      end

      def test_error_in_array_sequence_prefixItems
        ast = Psych.parse("- foo\n- 1")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "prefixItems" => [
              { "type" => "integer" },
              { "type" => "integer" },
            ]
          }, ast.children.first)
        end

        ast = Psych.parse("- foo\n- 1")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "prefixItems" => [
              { "type" => "string" },
              { "type" => "string" },
            ]
          }, ast.children.first)
        end
      end

      def test_invalid_string
        ast = Psych.parse("1")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end

        ast = Psych.parse("false")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end

        ast = Psych.parse("true")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end

        ast = Psych.parse("--- ")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end
      end

      def test_valid_quoted_string
        ast = Psych.parse("'1'")
        assert Validator.validate({
          "type" => "string",
        }, ast.children.first)

        ast = Psych.parse("'false'")
        assert Validator.validate({
          "type" => "string",
        }, ast.children.first)

        ast = Psych.parse("'true'")
        assert Validator.validate({
          "type" => "string",
        }, ast.children.first)

        ast = Psych.parse("--- ''")
        assert Validator.validate({
          "type" => "string",
        }, ast.children.first)
      end

      def test_multiple_valid
        ast = Psych.parse("'1'")
        assert Validator.validate({
          "type" => ["string", "integer"],
        }, ast.children.first)
      end

      def test_multiple_invalid
        ast = Psych.parse("'1'")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => ["null", "integer"],
          }, ast.children.first)
        end
      end

      def test_multiple_valid_array_type
        ast = Psych.parse("- '1'")
        assert Validator.validate({
          "type" => ["null", "array"],
          "items" => { "type" => "string" }
        }, ast.children.first)
      end

      def test_multiple_invalid_array_type
        ast = Psych.parse("- '1'")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => ["null", "array"],
            "items" => { "type" => "integer" }
          }, ast.children.first)
        end

        ast = Psych.parse("- 1\n- '123'")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => ["null", "array"],
            "items" => { "type" => "integer" }
          }, ast.children.first)
        end
      end

      def test_array_mixed_types
        ast = Psych.parse(<<-eoyml)
---
segments: 
- 3
- 0
- 0
- beta3
        eoyml
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "segments" => {
              "type" => "array",
              "items" => { "type" => ["integer", "string"] },
            }
          }
        }, ast.children.first)
      end

      def test_nullable_with_tag
        schema = {
          "type" => ["null", "object"],
          "tag" => "!foo",
          "properties" => {
            "segments" => { "type" => "string" }
          }
        }

        ast = Psych.parse(<<-eoyml)
--- !foo
segments: foo
        eoyml

        assert Validator.validate(schema, ast.children.first)

        ast = Psych.parse("---")

        assert Validator.validate(schema, ast.children.first)
      end

      def test_array_max_items
        ast = Psych.parse("- 0\n- 1")
        assert Validator.validate({
          "type" => "array",
          "items" => { "type" => "integer" },
          "maxItems" => 2,
        }, ast.children.first)

        ast = Psych.parse("- 0\n- 1")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "array",
            "items" => { "type" => "integer" },
            "maxItems" => 1,
          }, ast.children.first)
        end
      end

      def test_unexpected_tag
        ast = Psych.parse("--- !lolol\n foo")
        ex = assert_raises UnexpectedTag do
          Validator.validate({
            "type" => "string",
          }, ast.children.first)
        end
        assert_match(/lolol/, ex.message)
      end

      def test_object_without_specified_properties
        ast = Psych.parse("---\nfoo: bar")
        assert_raises InvalidSchema do
          Validator.validate({
            "type" => "object",
          }, ast.children.first)
        end
      end

      def test_invalid_sub_property
        ast = Psych.parse("---\nfoo: \n  hello: world")
        assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "object",
                "properties" => {
                  "hello" => {"type" => "integer"}
                }
              }
            }
          }, ast.children.first)
        end
      end

      def test_invalid_object_key_type # integer keys aren't allowed
        ast = Psych.parse("---\nfoo: \n  1: 2")
        ex = assert_raises UnexpectedValue do
          Validator.validate({
            "type" => "object",
            "properties" => {
              "foo" => {
                "type" => "object",
                "properties" => {
                  "hello" => {"type" => "integer"}
                }
              }
            }
          }, ast.children.first)
        end
        assert_match(/expected string, got integer/, ex.message)
      end

      def test_allow_objects_with_aliases
        ast = Psych.parse(<<-eoyml)
---
foo: &1
- foo
bar: *1
        eoyml
        assert Validator.validate({
          "type" => "object",
          "properties" => {
            "foo" => { "type" => "array", "items" => { "type" => "string" } },
            "bar" => { "type" => "array", "items" => { "type" => "string" } },
          },
        }, ast.children.first)
      end

      class CustomInfo
        def read_tag(node)
          if node.tag == "!aaron"
            "test"
          else
            node.tag
          end
        end
      end

      def test_custom_node_info
        validator = Validator.new(CustomInfo.new)
        ast = Psych.parse("--- !aaron\nfoo: bar")
        validator.validate({
          "type" => "object",
          "tag" => "test",
          "properties" => {
            "foo" => { "type" => "string" }
          }
        }, ast.children.first)
      end
    end
  end
end
