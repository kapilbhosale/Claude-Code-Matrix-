Gem::Specification.new do |spec|
  spec.name          = "claude-matrix"
  spec.version       = "1.0.0"
  spec.authors       = ["Kalpak"]
  spec.summary       = "Privacy-first TUI analytics dashboard for Claude Code"
  spec.description   = "Transforms your local Claude Code data into beautiful terminal insights"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"
  spec.files         = Dir["lib/**/*.rb", "bin/*", "config/*"]
  spec.bindir        = "bin"
  spec.executables   = ["claude-matrix"]

  spec.add_dependency "tty-box",    "~> 0.7"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "tty-reader", "~> 0.9"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "sqlite3",    "~> 1.7"
  spec.add_dependency "oj",         "~> 3.16"
end
