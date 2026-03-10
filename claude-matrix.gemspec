require_relative "lib/claude_matrix/version"

Gem::Specification.new do |spec|
  spec.name        = "claude-matrix"
  spec.version     = ClaudeMatrix::VERSION
  spec.authors     = ["Kapil Bhosale"]
  spec.email       = ["kapil@circle.co"]

  spec.summary     = "Privacy-first TUI analytics dashboard for Claude Code"
  spec.description = "Transforms your local ~/.claude/ session data into a beautiful " \
                     "btop-style terminal dashboard — streaks, tool usage, token costs, " \
                     "work modes, and activity heatmaps. No cloud, no API calls."
  spec.homepage    = "https://github.com/kapilbhosale/Claude-Code-Matrix"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri"   => "#{spec.homepage}/blob/main/CHANGELOG.md"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "bin/*",
    "README.md",
    "LICENSE",
    "CHANGELOG.md"
  ].reject { |f| File.directory?(f) }

  spec.bindir      = "bin"
  spec.executables = ["claude-matrix"]

  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-screen", "~> 0.8"
  spec.add_dependency "tty-reader", "~> 0.9"
  spec.add_dependency "pastel",     "~> 0.8"
  spec.add_dependency "oj",         "~> 3.16"
end
