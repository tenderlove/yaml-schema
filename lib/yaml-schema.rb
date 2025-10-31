# frozen_string_literal: true

module YAMLSchema
  class Validator
    class Exception < StandardError; end
    class UnexpectedType < Exception; end
    class UnexpectedProperty < Exception; end
    class UnexpectedTag < Exception; end
    class UnexpectedValue < Exception; end
    class InvalidSchema < Exception; end

    Valid = Struct.new(:exception).new.freeze

    ##
    # Given a particular schema, validate that the node conforms to the
    # schema. Raises an exception if it is invalid
    def self.validate(schema, node)
      INSTANCE.validate schema, node
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
    def validate(schema, node)
      val = _validate(schema["type"], schema, node, Valid, {}, ["root"])
      if val.exception
        raise val
      else
        true
      end
    end

    ##
    # Given a particular schema, validate that the node conforms to the
    # schema. Returns an error object if the node is invalid, otherwise false.
    def invalid?(schema, node)
      res = _validate(schema["type"], schema, node, Valid, {}, ["root"])
      if Valid == res
        false
      else
        res
      end
    end

    private

    def make_error(klass, msg, path)
      ex = klass.new msg + " path: #{path.join(" -> ")}"
      ex.set_backtrace caller
      ex
    end

    def _validate(type, schema, node, valid, aliases, path)
      return valid if valid.exception

      if node.anchor
        if node.alias?
          node = aliases[node.anchor]
        else
          aliases[node.anchor] = node
        end
      end

      tag = @node_info.read_tag(node)

      if Array === type
        v = valid
        type.each do |t|
          v = _validate t, schema, node, valid, aliases, path
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
          node.children.each_slice(2) do |key, val|
            valid = _validate("string", {}, key, valid, aliases, path)

            return valid if valid.exception

            sub_schema = properties.delete(key.value) {
              return make_error UnexpectedProperty, "unknown property #{key.value.dump}", path
            }
            valid = _validate(sub_schema["type"], sub_schema, val, valid, aliases, path + [key.value])

            return valid if valid.exception
          end
        else
          if schema["items"]
            sub_schema = schema["items"]
            node.children.each_slice(2) do |key, val|
              valid = _validate("string", {}, key, valid, aliases, path)
              return valid if valid.exception
              valid = _validate(sub_schema["type"], sub_schema, val, valid, aliases, path + [key.value])
              return valid if valid.exception
            end
          else
            raise InvalidSchema, "objects must specify items or properties"
          end
        end
      when "string"
        unless node.scalar?
          return make_error UnexpectedType, "expected Scalar, got #{node.class.name.dump}", path
        end

        unless node.quoted || node.tag == "!str"
          if node.value == "false" || node.value == "true"
            return make_error UnexpectedValue, "expected string, got boolean", path
          end

          if node.value == ""
            return make_error UnexpectedValue, "expected string, got null", path
          end

          if node.value.match?(/^[-+]?(?:0|[1-9](?:[0-9]|,[0-9]|_[0-9])*)$/)
            return make_error UnexpectedValue, "expected string, got integer", path
          end
        end
      when "array"
        unless node.sequence?
          return make_error UnexpectedType, "expected Sequence, got #{node.class.name.dump}", path
        end

        if schema["maxItems"] && node.children.length > schema["maxItems"]
          return make_error UnexpectedValue, "expected maximum #{schema["maxItems"]} items, but found #{node.children.length}", path
        end

        if schema["items"]
          node.children.each_with_index { |item, i|
            sub_schema = schema["items"]
            valid = _validate sub_schema["type"], sub_schema, item, valid, aliases, path + [i]
          }
        elsif schema["prefixItems"]
          node.children.each_with_index { |item, i|
            sub_schema = schema["prefixItems"][i]
            valid = _validate sub_schema["type"], sub_schema, item, valid, aliases, path + [i]
          }
        else
          raise NotImplementedError
        end
      when "null"
        unless node.scalar?
          return make_error UnexpectedType, "expected Scalar, got #{node.class.name.dump}", path
        end

        unless node.value == ""
          return make_error UnexpectedValue, "expected empty string, got #{node.value.dump}", path
        end
      when "boolean"
        unless node.scalar?
          return make_error UnexpectedType, "expected Scalar, got #{node.class.name.dump}", path
        end
        unless node.value == "false" || node.value == "true"
          return make_error UnexpectedValue, "expected 'true' or 'false' for boolean", path
        end
      when "integer"
        unless node.scalar?
          return make_error UnexpectedType, "expected Scalar, got #{node.class.name.dump}", path
        end
        if node.quoted
          return make_error UnexpectedValue, "expected integer, got string", path
        end
        unless node.value.match?(/^[-+]?(?:0|[1-9](?:[0-9]|,[0-9]|_[0-9])*)$/)
          return make_error UnexpectedValue, "expected integer, got string", path
        end
      else
        raise "unknown type #{schema["type"]}"
      end

      valid
    end
  end
end
