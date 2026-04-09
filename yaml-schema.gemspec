$: << File.expand_path("lib")
require "yaml-schema"

Gem::Specification.new do |s|
  s.name        = "yaml-schema"
  s.version     = YAMLSchema::VERSION
  s.summary     = "Validate YAML against a schema"
  s.description = "If you need to validate YAML against a schema, use this"
  s.authors     = ["Aaron Patterson"]
  s.email       = "tenderlove@ruby-lang.org"
  s.files       = `git ls-files -z`.split("\x0")
  s.test_files  = s.files.grep(%r{^test/})
  s.homepage    = "https://github.com/tenderlove/yaml-schema"
  s.license     = "Apache-2.0"

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'psych', '~> 5.0'
  s.add_development_dependency 'minitest', '>= 5.15'
end
