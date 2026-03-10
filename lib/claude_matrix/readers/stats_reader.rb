require "json"

module ClaudeMatrix
  module Readers
    class StatsReader
      STATS_PATH = File.expand_path("~/.claude/stats-cache.json")

      def self.available?
        File.exist?(STATS_PATH) && !File.empty?(STATS_PATH)
      end

      def self.read
        return nil unless available?
        JSON.parse(File.read(STATS_PATH))
      rescue JSON::ParserError
        nil
      end
    end
  end
end
