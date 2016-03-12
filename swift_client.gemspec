# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'swift_client/version'

Gem::Specification.new do |spec|
  spec.name          = "swift_client"
  spec.version       = SwiftClient::VERSION
  spec.authors       = ["Benjamin Vetter"]
  spec.email         = ["vetter@plainpicture.de"]
  spec.summary       = %q{Small but powerful client to interact with OpenStack Swift}
  spec.description   = %q{Small but powerful client to interact with OpenStack Swift}
  spec.homepage      = "https://github.com/mrkamel/swift_client"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty"
  spec.add_dependency "mime-types", "< 3.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "mocha"
end
