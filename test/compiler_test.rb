require "minitest/autorun"
require "yaml-schema"
require "psych"
require "tmpdir"
require "open3"
require "rbconfig"

module YAMLSchema
  class CompilerTest < Minitest::Test
    SCHEMAS = [
      { "type" => "string" },
      { "type" => "string", "minLength" => 2, "maxLength" => 4, "pattern" => /\A[a-z]+\z/ },
      { "type" => "integer" },
      { "type" => "integer", "pattern" => /\A1/ },
      { "type" => "float" },
      { "type" => "boolean" },
      { "type" => "null" },
      { "type" => "date" },
      { "type" => "time" },
      { "type" => "symbol" },
      { "type" => ["null", "string"] },
      { "type" => ["integer", "boolean", "string"] },
      { "type" => "array", "items" => { "type" => "integer" } },
      { "type" => "array", "items" => { "type" => "string" }, "minItems" => 1, "maxItems" => 2 },
      { "type" => "array", "prefixItems" => [{ "type" => "string" }, { "type" => "integer" }] },
      { "type" => "object", "items" => { "type" => "integer" } },
      { "type" => "object", "tag" => "!thing", "items" => { "type" => "string" } },
      { "type" => ["null", "object"], "tag" => "!thing", "items" => { "type" => "string" } },
      {
        "type" => "object",
        "properties" => {
          "name" => { "type" => "string" },
          "age"  => { "type" => ["null", "integer"] },
          "tags" => { "type" => "array", "items" => { "type" => "string" } },
        },
        "required" => ["name", "age"],
      },
      {
        "type" => "object",
        "properties" => { "a" => { "type" => "integer" } },
        "additionalProperties" => { "type" => "boolean" },
        "propertyNames" => { "pattern" => /\A[a-z]\z/, "maxLength" => 1 },
      },
      {
        "type" => "object",
        "properties" => {
          "users" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "name" => { "type" => "string" },
                "meta" => { "type" => "object", "items" => { "type" => ["string", "integer"] } },
              },
              "required" => ["name"],
            },
          },
        },
      },
    ]

    DOCUMENTS = [
      "foo", "'foo'", "\"123\"", "123", "0x1f", "1.5", ".inf", "true", "yes",
      "", "~", "null", "2024-01-02", "2024-01-02 10:11:12", ":sym", "abcdef",
      "!str 123", "!thing foo", "ab", "a1",
      "- 1\n- 2", "- foo\n- 1", "- foo\n- bar\n- baz", "[]", "- a\n- 1\n- extra",
      "a: 1", "a: true\nb: false", "a: 1\na: true", "ab: 1", "1: 1",
      "!thing\na: b", "!other\na: b", "{}",
      "name: bob\nage: 1", "name: bob", "name: bob\nage:\ntags:\n- x", "name: bob\nage: 1\nextra: 1",
      "name: 1\nage: 1", "age: x",
      "users:\n- name: a\n  meta:\n    x: 1\n    y: z\n- name: b", "users:\n- meta: {}",
      "users:\n- name: a\n  meta:\n    x: [1]",
      "a: &x 1\nb: *x", "x: &x\n- 1\ny: *x",
    ]

    def outcome
      [:ok, yield]
    rescue Validator::Exception => e
      [e.class, e.message]
    rescue => e
      [:crash, e.class]
    end

    # Stand-alone validators define their own exception classes, so compare
    # exceptions by their unqualified names.
    def loose_outcome
      [:ok, yield]
    rescue => e
      # An exception raised without a message uses its class name as the message
      message = e.message == e.class.name ? :default : e.message
      [e.class.name.split("::").last, message]
    end

    def standalone_validator schema
      mod = Module.new
      mod.module_eval Compiler.to_ruby(schema, class_name: "Validator", standalone: true)
      mod::Validator
    end

    def test_compiled_matches_interpreter
      SCHEMAS.each do |schema|
        compiled = Compiler.compile(schema)
        DOCUMENTS.each do |yaml|
          node = Psych.parse("---\n#{yaml}").children.first
          [true, false].each do |aliases|
            expected = outcome { Validator.validate(schema, node, aliases: aliases) }
            actual   = outcome { compiled.validate(node, aliases: aliases) }
            assert_equal expected, actual, "schema=#{schema.inspect} yaml=#{yaml.inspect} aliases=#{aliases}"

            expected = outcome { e = Validator.new.invalid?(schema, node, aliases: aliases); e && [e.class, e.message] }
            actual   = outcome { e = compiled.invalid?(node, aliases: aliases); e && [e.class, e.message] }
            assert_equal expected, actual, "invalid? schema=#{schema.inspect} yaml=#{yaml.inspect}"
          end
        end
      end
    end

    def test_standalone_matches_interpreter
      SCHEMAS.each do |schema|
        standalone = standalone_validator(schema)
        refute_operator standalone, :<, CompiledValidator

        DOCUMENTS.each do |yaml|
          node = Psych.parse("---\n#{yaml}").children.first
          [true, false].each do |aliases|
            expected = loose_outcome { Validator.validate(schema, node, aliases: aliases) }
            actual   = loose_outcome { standalone.validate(node, aliases: aliases) }
            assert_equal expected, actual, "schema=#{schema.inspect} yaml=#{yaml.inspect} aliases=#{aliases}"
          end
        end
      end
    end

    def test_standalone_runs_without_yaml_schema
      schema = { "type" => "object", "properties" => { "age" => { "type" => "integer" } } }
      script = <<~'RUBY'
        require "psych"
        load ARGV.fetch(0)
        abort "yaml-schema was loaded" if defined?(YAMLSchema)
        puts AgeValidator.validate(Psych.parse("age: 1").children.first)
        begin
          AgeValidator.validate(Psych.parse("age: x").children.first)
        rescue AgeValidator::UnexpectedValue => e
          puts e.message
        end
      RUBY

      Dir.mktmpdir do |dir|
        path = File.join(dir, "age_validator.rb")
        File.write path, Compiler.to_ruby(schema, class_name: "AgeValidator", standalone: true)

        # Clear RUBYOPT so bundler/setup doesn't load the gemspec (which requires yaml-schema)
        env = { "RUBYOPT" => nil, "RUBYLIB" => nil }
        out, err, status = Open3.capture3(env, RbConfig.ruby, "--disable-gems", "-e", script, path)
        assert status.success?, err
        assert_equal "true\nexpected integer, got string path: /age\n", out
      end
    end

    def test_validate_and_invalid?
      v = Compiler.compile({ "type" => "array", "items" => { "type" => "integer" } })
      assert v.validate(Psych.parse("- 1").children.first)
      refute v.invalid?(Psych.parse("- 1").children.first)

      node = Psych.parse("- 1\n- foo").children.first
      err = v.invalid?(node)
      assert_kind_of Validator::UnexpectedValue, err
      assert_match %r{path: /1}, err.message
      assert_raises(Validator::UnexpectedValue) { v.validate(node) }
    end

    def test_invalid_schema_raises_at_compile_time
      assert_raises(Validator::InvalidSchema) { Compiler.compile({ "type" => "nope" }) }
    end

    def test_custom_node_info
      info = Object.new
      def info.read_tag(node); node.tag == "!aaron" ? "test" : node.tag; end
      v = Compiler.compile({ "type" => "object", "tag" => "test", "properties" => { "foo" => { "type" => "string" } } })
      node = Psych.parse("--- !aaron\nfoo: bar").children.first
      assert v.new(info).validate(node)
      assert_raises(Validator::UnexpectedTag) { v.validate(node) }
    end

    def test_extra_prefix_items_are_allowed
      v = Compiler.compile({ "type" => "array", "prefixItems" => [{ "type" => "string" }] })
      assert v.validate(Psych.parse("- a\n- 1").children.first)
    end

    def test_to_ruby
      schema = { "type" => "object", "properties" => { "name" => { "type" => "string", "pattern" => %r{\A/\w+\z}i } } }
      src = Compiler.to_ruby(schema, class_name: "GeneratedPersonValidator")

      Dir.mktmpdir do |dir|
        path = File.join(dir, "generated_person_validator.rb")
        File.write path, src
        load path
      end

      assert_operator GeneratedPersonValidator, :<, CompiledValidator
      assert GeneratedPersonValidator.validate(Psych.parse("name: /Bob").children.first)
      assert_raises(Validator::InvalidPattern) do
        GeneratedPersonValidator.validate(Psych.parse("name: bob").children.first)
      end
    ensure
      YAMLSchema.send(:remove_const, :GeneratedPersonValidator) if YAMLSchema.const_defined?(:GeneratedPersonValidator, false)
      Object.send(:remove_const, :GeneratedPersonValidator) if Object.const_defined?(:GeneratedPersonValidator, false)
    end
  end
end
