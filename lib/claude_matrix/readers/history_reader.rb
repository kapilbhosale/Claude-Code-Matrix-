require "json"

module ClaudeMatrix
  module Readers
    class HistoryReader
      HISTORY_PATH = File.expand_path("~/.claude/history.jsonl")

      def self.read
        return [] unless File.exist?(HISTORY_PATH)

        File.readlines(HISTORY_PATH, chomp: true).filter_map do |line|
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
      end

      def self.top_words(limit: 10)
        stop_words = %w[i a the an is it in on at to for of and or but
                        this that with from can you what how do be have
                        are was were will would could should may might
                        its your my we our let me now please just also
                        if so there not no yes then when they he she]

        all_words = read.flat_map do |entry|
          text = entry["display"].to_s.downcase
          text.scan(/[a-z]{3,}/)
        end

        all_words
          .reject { |w| stop_words.include?(w) }
          .tally
          .sort_by { |_, count| -count }
          .first(limit)
      end
    end
  end
end
