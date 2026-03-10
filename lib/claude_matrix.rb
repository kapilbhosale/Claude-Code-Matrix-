require_relative "claude_matrix/version"
require_relative "claude_matrix/readers/stats_reader"
require_relative "claude_matrix/readers/session_parser"
require_relative "claude_matrix/readers/history_reader"
require_relative "claude_matrix/analyzers/metrics"
require_relative "claude_matrix/visualizers/dashboard"

module ClaudeMatrix

  def self.load_sessions(verbose: false)
    files = Readers::SessionParser.jsonl_files
    if files.empty?
      warn "No Claude Code session files found in ~/.claude/projects/"
      return []
    end

    if verbose
      $stderr.print "Scanning #{files.size} session files..."
    end

    sessions = []
    files.each_with_index do |file, i|
      if verbose && (i % 10 == 0)
        $stderr.print "\rParsing sessions... #{i+1}/#{files.size}"
        $stderr.flush
      end
      s = Readers::SessionParser.parse_file(file)
      sessions << s if s
    end

    $stderr.puts "\r#{' ' * 50}\r" if verbose
    sessions
  end
end
