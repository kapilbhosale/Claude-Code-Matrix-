require "json"
require "time"

module ClaudeMatrix
  module Readers
    class SessionParser
      PROJECTS_PATH = File.expand_path("~/.claude/projects")

      # Returns array of parsed session hashes
      def self.parse_all(&progress_block)
        sessions = []
        all_files = jsonl_files

        all_files.each_with_index do |file, i|
          progress_block&.call(i + 1, all_files.size)
          session = parse_file(file)
          sessions << session if session
        end

        sessions
      end

      def self.jsonl_files
        return [] unless Dir.exist?(PROJECTS_PATH)
        Dir.glob("#{PROJECTS_PATH}/**/*.jsonl").sort
      end

      def self.project_name_from_path(file_path)
        # ~/.claude/projects/-Users-foo-Work-circle/session.jsonl
        # => "circle"
        parts = file_path.split("/")
        encoded = parts[-2]
        decoded = encoded.gsub("-", "/").sub(%r{^/}, "")
        decoded.split("/").last || encoded
      end

      def self.parse_file(file_path)
        lines = File.readlines(file_path, chomp: true).reject(&:empty?)
        return nil if lines.empty?

        tools       = []
        timestamps  = []
        input_tokens  = 0
        output_tokens = 0
        cache_read    = 0
        cache_create  = 0
        model         = nil
        git_branch    = nil
        session_id    = nil
        cwd           = nil

        prompt_words = []
        prompt_count = 0

        lines.each do |line|
          data = JSON.parse(line)

          session_id  ||= data["sessionId"]
          git_branch  ||= data["gitBranch"]
          cwd         ||= data["cwd"]

          ts = data["timestamp"]
          timestamps << Time.parse(ts) if ts

          if data["type"] == "assistant"
            msg = data["message"] || {}
            model ||= msg["model"]

            # token usage
            usage = data["usage"] || msg["usage"] || {}
            input_tokens  += (usage["input_tokens"]                || 0)
            output_tokens += (usage["output_tokens"]               || 0)
            cache_read    += (usage["cache_read_input_tokens"]     || 0)
            cache_create  += (usage["cache_creation_input_tokens"] || 0)

            # tool calls
            content = msg["content"] || []
            content.each do |block|
              tools << block["name"] if block["type"] == "tool_use" && block["name"]
            end

          elsif data["type"] == "user"
            # Extract prompt text (skip tool_result blocks — only human text)
            content = data.dig("message", "content")
            texts = case content
                    when Array  then content.select { |b| b["type"] == "text" }.map { |b| b["text"].to_s }
                    when String then [content]
                    else []
                    end
            text = texts.join(" ").strip
            unless text.empty?
              words = text.split(/\s+/).map { |w| w.downcase.gsub(/[^a-z0-9']/, "") }
                         .reject { |w| w.length < 2 }
              prompt_words.concat(words)
              prompt_count += 1
            end
          end
        rescue JSON::ParserError
          next
        end

        return nil if timestamps.empty?

        project_path = File.dirname(file_path)
        file_name    = File.basename(file_path, ".jsonl")

        {
          session_id:    session_id || file_name,
          file:          file_path,
          project:       project_name_from_path(file_path),
          project_path:  cwd || project_path,
          git_branch:    git_branch,
          started_at:    timestamps.min,
          ended_at:      timestamps.max,
          duration_secs: (timestamps.max - timestamps.min).to_i,
          message_count: lines.count { |l| l.include?('"type":"user"') || l.include?('"type": "user"') },
          tools:         tools,
          tool_count:    tools.size,
          model:         model,
          input_tokens:  input_tokens,
          output_tokens: output_tokens,
          cache_read:    cache_read,
          cache_create:  cache_create,
          prompt_words:  prompt_words,
          prompt_count:  prompt_count
        }
      rescue => e
        nil
      end
    end
  end
end
