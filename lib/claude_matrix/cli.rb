require_relative "../claude_matrix"
require "tty-reader"
require "tty-cursor"
require "date"

module ClaudeMatrix
  class CLI
    def self.run(args)
      case (args.first || "dashboard")
      when "dashboard", "d", nil then DashboardCommand.new.run
      when "stats"                then StatsCommand.new(args[1..]).run
      when "sync"                 then SyncCommand.new.run
      when "doctor"               then DoctorCommand.new.run
      when "version", "--version", "-v" then puts "claude-matrix #{VERSION}"
      when "help", "--help", "-h"       then puts help_text
      else
        warn "Unknown command: #{args.first}"
        warn help_text
        exit 1
      end
    end

    def self.help_text
      <<~HELP
        Claude Matrix #{VERSION} — Claude Code Analytics Dashboard

        Usage:
          claude-matrix              Launch interactive dashboard
          claude-matrix stats        Print stats to stdout
          claude-matrix stats --today / --week / --month
          claude-matrix doctor       Check data sources
          claude-matrix version

        Dashboard keys:
          t/w/m/a  Filter: Today / Week / Month / All Time
          r        Refresh
          q        Quit
      HELP
    end

    # ─── Interactive dashboard ────────────────────────────────────────────────

    class DashboardCommand
      FILTERS = %i[today week month all].freeze

      def run
        cursor  = TTY::Cursor
        reader  = TTY::Reader.new(interrupt: :exit)
        filter  = :all
        all_sessions = nil  # lazy-load once, refresh on 'r'

        loop do
          all_sessions ||= ClaudeMatrix.load_sessions
          metrics = Analyzers::Metrics.compute(filter_sessions(all_sessions, filter))

          print cursor.clear_screen
          print cursor.move_to(0, 0)
          Visualizers::Dashboard.new(metrics, filter: filter).render

          char = reader.read_char
          case char&.downcase
          when "q", "\e" then break
          when "r"        then all_sessions = nil  # force reload
          when "t"        then filter = :today
          when "w"        then filter = :week
          when "m"        then filter = :month
          when "a"        then filter = :all
          end
        end
      rescue TTY::Reader::InputInterrupt
        # clean exit on Ctrl-C
      ensure
        puts TTY::Cursor.show
        puts  # move off last dashboard line
      end

      private

      def filter_sessions(sessions, filter)
        case filter
        when :today
          d = Date.today
          sessions.select { |s| s[:started_at].to_date == d }
        when :week
          start = Date.today - Date.today.wday
          sessions.select { |s| s[:started_at].to_date >= start }
        when :month
          sessions.select { |s|
            s[:started_at].year == Date.today.year &&
            s[:started_at].month == Date.today.month
          }
        else
          sessions
        end
      end
    end

    # ─── Stats command ────────────────────────────────────────────────────────

    class StatsCommand
      def initialize(flags)
        @filter = if flags.include?("--today") then :today
                  elsif flags.include?("--week")  then :week
                  elsif flags.include?("--month") then :month
                  else :all
                  end
      end

      def run
        all  = ClaudeMatrix.load_sessions
        sess = filter_sessions(all, @filter)
        m    = Analyzers::Metrics.compute(sess)

        label = { today: "Today", week: "This Week", month: "This Month", all: "All Time" }[@filter]
        puts "\n  Claude Matrix — #{label}"
        puts "  " + "─" * 40
        puts "  Sessions:    #{m[:total_sessions]}"
        puts "  Messages:    #{m[:total_messages]}"
        puts "  Tools:       #{m[:total_tool_calls]}"
        puts "  Tokens In:   #{fmt(m[:total_input_tokens])}"
        puts "  Tokens Out:  #{fmt(m[:total_output_tokens])}"
        puts "  Est. Cost:   $#{"%.4f" % m[:estimated_cost]}"
        puts "  Streak:      #{m[:streaks][:current]} days (best: #{m[:streaks][:longest]})"
        puts "  Top Tool:    #{m[:favorite_tool]} (#{m[:tool_counts][m[:favorite_tool]]})" if m[:favorite_tool]
        puts
      end

      private

      def filter_sessions(sessions, filter)
        DashboardCommand.new.send(:filter_sessions, sessions, filter)
      end

      def fmt(n)
        n >= 1_000_000 ? "%.1fM" % (n / 1_000_000.0) :
        n >= 1_000     ? "%.1fK" % (n / 1_000.0) : n.to_s
      end
    end

    # ─── Sync command ─────────────────────────────────────────────────────────

    class SyncCommand
      def run
        files = Readers::SessionParser.jsonl_files
        puts "\nScanning #{files.size} session files..."
        count = 0
        files.each_with_index do |f, i|
          print "\rParsing #{i + 1}/#{files.size}..."
          count += 1 if Readers::SessionParser.parse_file(f)
        end
        puts "\rDone! #{count}/#{files.size} sessions parsed.   "
        puts "Run 'claude-matrix' to view the dashboard."
      end
    end

    # ─── Doctor command ───────────────────────────────────────────────────────

    class DoctorCommand
      def run
        puts "\n  Claude Matrix — Doctor\n  " + "─" * 36
        check "~/.claude/ exists",            Dir.exist?(File.expand_path("~/.claude"))
        check "~/.claude/projects/ exists",   Dir.exist?(File.expand_path("~/.claude/projects"))
        check "~/.claude/history.jsonl",      File.exist?(File.expand_path("~/.claude/history.jsonl"))
        check "stats-cache.json",             Readers::StatsReader.available?
        files = Readers::SessionParser.jsonl_files
        check "Session files found (#{files.size})", files.any?
        puts
      end

      private

      def check(label, ok)
        puts "  #{ok ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"}  #{label}"
      end
    end
  end
end
