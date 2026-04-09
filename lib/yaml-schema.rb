# frozen_string_literal: true

module YAMLSchema
  VERSION = "1.2.0"

  class Pointer
    include Enumerable

    class Exception < StandardError; end
    class FormatError < Exception; end

    def initialize path
      @path = Pointer.parse path
    end

    def each(&block); @path.each(&block); end

    def eval object
      Pointer.eval @path, object
    end
    alias :[] :eval

    ESC = {'^/' => '/', '^^' => '^', '~0' => '~', '~1' => '/'} # :nodoc:

    def self.[] path, object
      eval parse(path), object
    end

    def self.eval list, object # :nodoc:
      object = object.children.first if object.document?

      list.inject(object) { |o, part|
        return nil unless o

        if o.sequence?
          raise IndexError unless part =~ /\A(?:\d|[1-9]\d+)\Z/
          o.children.fetch(part.to_i)
        else
          o.children.each_slice(2) do |key, value|
            if key.value == part
              break value
            end
          end
        end
      }
    end

    def self.parse path
      return [''] if path == '/'
      return []   if path == ''

      unless path.start_with? '/'
        raise FormatError, "Pointer should start with a slash"
      end

      parts = path.sub(/^\//, '').split(/(?<!\^)\//).each { |part|
        part.gsub!(/\^[\/^]|~[01]/) { |m| ESC[m] }
      }

      parts.push("") if path[-1] == '/'
      parts
    end
  end

  class Validator
    class Exception < StandardError; end
    class UnexpectedType < Exception; end
    class UnexpectedProperty < Exception; end
    class UnexpectedTag < Exception; end
    class UnexpectedValue < Exception; end
    class UnexpectedAlias < Exception; end
    class InvalidSchema < Exception; end
    class InvalidString < Exception; end
    class InvalidPattern < Exception; end
    class MissingRequiredField < Exception; end

    Valid = Struct.new(:exception).new.freeze

    ##
    # Given a particular schema, validate that the node conforms to the
    # schema. Raises an exception if it is invalid
    def self.validate(schema, node, aliases: true)
      INSTANCE.validate schema, node, aliases: aliases
    end

    module NodeInfo # :nodoc:
      def self.read_tag(node)
        node.tag
      end
    end

    def initialize(node_info = NodeInfo)
      @node_info = node_info
    end

    INSTANCE = new.freeze

    ##
    # Given a particular schema, validate that the node conforms to the
    # schema. Raises an exception if it is invalid
    def validate(schema, node, aliases: true)
      val = _validate(schema["type"], schema, node, Valid, {}, [], aliases)
      if val.exception
        raise val
      else
        true
      end
    end

    ##
    # Given a particular schema, validate that the node conforms to the
    # schema. Returns an error object if the node is invalid, otherwise false.
    def invalid?(schema, node, aliases: true)
      res = _validate(schema["type"], schema, node, Valid, {}, [], aliases)
      if Valid == res
        false
      else
        res
      end
    end

    private

    def make_error(klass, msg, path)
      ex = klass.new msg + " path: /#{path.join("/")}"
      ex.set_backtrace caller
      ex
    end

    def _validate(type, schema, node, valid, aliases, path, allow_aliases)
      return valid if valid.exception

      if node.anchor
        if node.alias?
          raise UnexpectedAlias unless allow_aliases
          node = aliases[node.anchor]
        else
          aliases[node.anchor] = node
        end
      end

      tag = @node_info.read_tag(node)

      if Array === type
        v = valid
        type.each do |t|
          v = _validate t, schema, node, valid, aliases, path, allow_aliases
          unless v.exception
            break
          end
        end
        valid = v
        return valid
      end

      if type == "object"
        if tag != schema["tag"]
          if schema["tag"]
            if node.tag
              return make_error UnexpectedTag, "expected tag #{schema["tag"].dump}, but got #{node.tag.dump}", path
            else
              return make_error UnexpectedTag, "expected tag #{schema["tag"].dump}, but none specified", path
            end
          else
            return make_error UnexpectedTag, "expected no tag, but got #{node.tag.dump}", path
          end
        end
      else
        if tag
          return make_error UnexpectedTag, "expected no tag, but got #{node.tag.dump}", path
        end
      end

      case type
      when "object"
        unless node.mapping?
          return make_error UnexpectedType, "expected Mapping, got #{node.class.name.dump}", path
        end
        if schema["properties"]
          properties = schema["properties"].dup
          key_restriction = schema["propertyNames"] || {}
          node.children.each_slice(2) do |key, val|
            valid = _validate("string", key_restriction, key, valid, aliases, path, allow_aliases)

            return valid if valid.exception

            sub_schema = properties.delete(key.value) {
              if schema["additionalProperties"]
                schema["additionalProperties"]
              else
                return make_error UnexpectedProperty, "unknown property #{key.value.dump}", path + [key.value]
              end
            }

            valid = _validate(sub_schema["type"], sub_schema, val, valid, aliases, path + [key.value], allow_aliases)

            return valid if valid.exception
          end

          if schema["required"]
            missing_fields = properties.keys & schema["required"]
            unless missing_fields.empty?
              return make_error MissingRequiredField, "missing fields #{missing_fields.map(&:dump).join(" ")}", path
            end
          end
        else
          if schema["items"]
            sub_schema = schema["items"]
            node.children.each_slice(2) do |key, val|
              valid = _validate("string", {}, key, valid, aliases, path, allow_aliases)
              return valid if valid.exception
              valid = _validate(sub_schema["type"], sub_schema, val, valid, aliases, path + [key.value], allow_aliases)
              return valid if valid.exception
            end
          else
            raise InvalidSchema, "objects must specify items or properties"
          end
        end
      when "array"
        unless node.sequence?
          return make_error UnexpectedType, "expected Sequence, got #{node.class.name.dump}", path
        end

        if schema["maxItems"] && node.children.length > schema["maxItems"]
          return make_error UnexpectedValue, "expected maximum #{schema["maxItems"]} items, but found #{node.children.length}", path
        end

        if schema["minItems"] && node.children.length < schema["minItems"]
          return make_error UnexpectedValue, "expected minimum #{schema["minItems"]} items, but found #{node.children.length}", path
        end

        if schema["items"]
          node.children.each_with_index { |item, i|
            sub_schema = schema["items"]
            valid = _validate sub_schema["type"], sub_schema, item, valid, aliases, path + [i], allow_aliases
          }
        elsif schema["prefixItems"]
          node.children.each_with_index { |item, i|
            sub_schema = schema["prefixItems"][i]
            valid = _validate sub_schema["type"], sub_schema, item, valid, aliases, path + [i], allow_aliases
          }
        else
          raise NotImplementedError
        end
      else
        unless node.scalar?
          return make_error UnexpectedType, "expected Scalar, got #{node.class.name.dump}", path
        end

        if type == "string"
          unless node.quoted || node.tag == "!str"
            type = extract_type(node.value)

            if type != :string
              return make_error UnexpectedValue, "expected string, got #{type}", path
            end
          end

          if schema["maxLength"] && node.value.bytesize > schema["maxLength"]
            return make_error InvalidString, "expected string length to be <= #{schema["maxLength"]}", path
          end

          if schema["minLength"] && node.value.bytesize < schema["minLength"]
            return make_error InvalidString, "expected string length to be >= #{schema["minLength"]}", path
          end

          if schema["pattern"] && !(node.value.match?(schema["pattern"]))
            return make_error InvalidPattern, "expected string '#{node.value.dump}' to match #{schema["pattern"]}", path
          end
        else
          if node.quoted
            return make_error UnexpectedValue, "expected #{type}, got string", path
          end

          if type == "null"
            unless node.value == ""
              return make_error UnexpectedValue, "expected empty string, got #{node.value.dump}", path
            end
          else
            if schema["pattern"] && !(node.value.match?(schema["pattern"]))
              return make_error InvalidPattern, "expected '#{node.value.dump}' to match #{schema["pattern"]}", path
            end

            case type
            when "boolean"
              unless node.value == "false" || node.value == "true"
                return make_error UnexpectedValue, "expected 'true' or 'false' for boolean", path
              end
            when "integer", "float", "time", "date", "symbol"
              found_type = extract_type(node.value)
              unless found_type == type.to_sym
                return make_error UnexpectedValue, "expected #{type}, got #{found_type}", path
              end
            else
              raise "unknown type #{schema["type"]}"
            end
          end
        end
      end

      valid
    end

    # Taken from http://yaml.org/type/timestamp.html
    TIME = /^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$/

    # Taken from http://yaml.org/type/float.html
    # Base 60, [-+]inf and NaN are handled separately
    FLOAT = /^(?:[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?(?# base 10))$/x

    # Taken from http://yaml.org/type/int.html and modified to ensure at least one numerical symbol exists
    INTEGER_STRICT = /^(?:[-+]?0b[_]*[0-1][0-1_]*             (?# base 2)
                         |[-+]?0[_]*[0-7][0-7_]*              (?# base 8)
                         |[-+]?(0|[1-9][0-9_]*)               (?# base 10)
                         |[-+]?0x[_]*[0-9a-fA-F][0-9a-fA-F_]* (?# base 16))$/x

    # Tokenize +string+ returning the Ruby object
    def extract_type(string)
      return :null if string.empty?
      # Check for a String type, being careful not to get caught by hash keys, hex values, and
      # special floats (e.g., -.inf).
      if string.match?(%r{^[^\d.:-]?[[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=]+}) || string.match?(/\n/)
        return :string if string.length > 5

        if string.match?(/^[^ytonf~]/i)
          :string
        elsif string == '~' || string.match?(/^null$/i)
          :null
        elsif string.match?(/^(yes|true|on)$/i)
          :boolean
        elsif string.match?(/^(no|false|off)$/i)
          :boolean
        else
          :string
        end
      elsif string.match?(TIME)
        :time
      elsif string.match?(/^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$/)
        :date
      elsif string.match?(/^\+?\.inf$/i)
        :float
      elsif string.match?(/^-\.inf$/i)
        :float
      elsif string.match?(/^\.nan$/i)
        :float
      elsif string.match?(/^:./)
        :symbol
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}$/)
        :sexagesimal
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}\.[0-9_]*$/)
        :sexagesimal
      elsif string.match?(FLOAT)
        if string.match?(/\A[-+]?\.\Z/)
          :string
        else
          :float
        end
      elsif string.match?(INTEGER_STRICT)
        :integer
      else
        :string
      end
    end
  end
end
