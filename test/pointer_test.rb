require "minitest/autorun"
require "yaml-schema"
require "psych"

module YAMLSchema
  class PointerTest < Minitest::Test
    def test_value
      ast = Psych.parse("---\n  hello: world")
      pointer = YAMLSchema::Pointer.new("/hello")
      assert_equal "world", pointer.eval(ast).value
      assert_equal "world", pointer.eval(ast.children.first).value
    end

    def test_nested_values
      ast = Psych.parse("---\n  hello: \n    nested: world")
      pointer = YAMLSchema::Pointer.new("/hello/nested")
      assert_equal "world", pointer.eval(ast).value
      assert_equal "world", pointer.eval(ast.children.first).value
    end

    def test_array_part
      ast = Psych.parse("---\n- a\n- b\n- c")
      pointer = YAMLSchema::Pointer.new("/0")
      assert_equal "a", pointer.eval(ast).value
      assert_equal "a", pointer[ast].value
      assert_equal "b", Pointer["/1", ast].value
      assert_equal "c", Pointer["/2", ast].value
      assert_raises(IndexError) { Pointer["/3", ast] }
    end

    def test_map_key
      ast = Psych.parse("---\n- a\n- b\n- c")
      assert_raises(IndexError) { Pointer["/foo", ast] }
    end
  end
end
