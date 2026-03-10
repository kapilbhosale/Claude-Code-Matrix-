require "date"

module ClaudeMatrix
  module Analyzers
    class Metrics
      # Claude pricing per 1M tokens (as of early 2026)
      MODEL_PRICING = {
        "claude-opus-4-6"             => { input: 15.0,  output: 75.0,  cache_read: 1.5,  cache_write: 18.75 },
        "claude-opus-4-5"             => { input: 15.0,  output: 75.0,  cache_read: 1.5,  cache_write: 18.75 },
        "claude-sonnet-4-6"           => { input: 3.0,   output: 15.0,  cache_read: 0.3,  cache_write: 3.75  },
        "claude-sonnet-4-5"           => { input: 3.0,   output: 15.0,  cache_read: 0.3,  cache_write: 3.75  },
        "claude-haiku-4-5-20251001"   => { input: 0.8,   output: 4.0,   cache_read: 0.08, cache_write: 1.0   },
        "claude-haiku-4-5"            => { input: 0.8,   output: 4.0,   cache_read: 0.08, cache_write: 1.0   },
      }.freeze

      DEFAULT_PRICE = { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 }.freeze

      STOPWORDS = %w[
        the a an and or but in on at to for of is it i my with this that you we
        can be are was were have had do does did will would could should may might
        must shall from by about as into through during before after above below
        up down out off over under again further then once here there when where
        why how all both each few more most other some such no nor not only own
        same so than too very just because if while please let me make get how
        what use new add your its im its just also want need its
      ].freeze

      WORK_MODE_TOOLS = {
        exploration: %w[Read Glob Grep WebSearch WebFetch read_file list_files search_files grep],
        building:    %w[Write Edit NotebookEdit write_to_file edit_file new_file],
        testing:     %w[Bash execute_command bash]
      }.freeze

      def self.compute(sessions)
        return empty_metrics if sessions.empty?

        total_input    = sessions.sum { |s| s[:input_tokens] }
        total_output   = sessions.sum { |s| s[:output_tokens] }
        total_cache_r  = sessions.sum { |s| s[:cache_read] }
        total_cache_w  = sessions.sum { |s| s[:cache_create] }

        all_tools   = sessions.flat_map { |s| s[:tools] }
        tool_counts = all_tools.tally.sort_by { |_, c| -c }.to_h

        daily = build_daily_activity(sessions)
        streaks = calculate_streaks(daily)
        hour_counts = build_hour_counts(sessions)

        longest = sessions.max_by { |s| s[:duration_secs] }
        most_messages = sessions.max_by { |s| s[:message_count] }

        projects = sessions.group_by { |s| s[:project] }
        most_active_project = projects.max_by { |_, ss| ss.sum { |s| s[:message_count] } }&.first

        all_prompt_words = sessions.flat_map { |s| s[:prompt_words] || [] }
        total_prompts    = sessions.sum { |s| s[:prompt_count] || 0 }
        avg_words        = total_prompts > 0 ? (all_prompt_words.size.to_f / total_prompts).round : 0

        {
          total_sessions:    sessions.size,
          total_messages:    sessions.sum { |s| s[:message_count] },
          total_tool_calls:  all_tools.size,
          total_input_tokens:  total_input,
          total_output_tokens: total_output,
          total_cache_read:    total_cache_r,
          total_cache_write:   total_cache_w,
          estimated_cost:    estimate_cost(sessions),
          first_session:     sessions.map { |s| s[:started_at] }.min,
          projects:          projects.keys.size,
          project_names:     projects.keys,
          most_active_project: most_active_project,
          tool_counts:       tool_counts,
          top_tools:         tool_counts.first(10).to_h,
          favorite_tool:     tool_counts.first&.first,
          daily_activity:    daily,
          daily_cost:        build_daily_cost(sessions),
          streaks:           streaks,
          hour_counts:       hour_counts,
          hour_day_grid:     build_hour_day_grid(sessions),
          work_modes:        calculate_work_modes(all_tools),
          longest_session:   longest,
          most_messages_session: most_messages,
          most_productive_day: most_productive_day(daily),
          busiest_hour:      hour_counts.max_by { |_, c| c }&.first,
          models_used:       sessions.map { |s| s[:model] }.compact.uniq,
          models_breakdown:  build_models_breakdown(sessions),
          total_prompts:     total_prompts,
          avg_prompt_words:  avg_words,
          top_prompt_words:  top_prompt_words(all_prompt_words),
          per_project:       build_per_project(sessions)
        }
      end

      def self.estimate_cost(sessions)
        total = 0.0
        sessions.each do |s|
          price = find_price(s[:model])
          total += (s[:input_tokens].to_f  / 1_000_000) * price[:input]
          total += (s[:output_tokens].to_f / 1_000_000) * price[:output]
          total += (s[:cache_read].to_f    / 1_000_000) * price[:cache_read]
          total += (s[:cache_create].to_f  / 1_000_000) * price[:cache_write]
        end
        total.round(4)
      end

      private

      def self.find_price(model)
        return DEFAULT_PRICE unless model
        MODEL_PRICING.find { |k, _| model.start_with?(k) }&.last || DEFAULT_PRICE
      end

      def self.build_daily_activity(sessions)
        daily = Hash.new { |h, k| h[k] = { sessions: 0, messages: 0, tools: 0 } }

        sessions.each do |s|
          date = s[:started_at].to_date.to_s
          daily[date][:sessions]  += 1
          daily[date][:messages]  += s[:message_count]
          daily[date][:tools]     += s[:tool_count]
        end

        daily.sort.to_h
      end

      def self.calculate_streaks(daily)
        return { current: 0, longest: 0, active_days: 0 } if daily.empty?

        dates = daily.keys.map { |d| Date.parse(d) }.sort
        active_days = dates.size

        # Current streak
        current = 0
        expected = Date.today
        dates.sort.reverse.each do |date|
          break if date < expected - 1
          if date == expected || date == expected - 1
            current += 1
            expected = date - 1
          end
        end

        # Also allow today to count if used today
        current = 1 if current == 0 && dates.include?(Date.today)

        # Longest streak
        longest = 1
        temp = 1
        dates.each_cons(2) do |d1, d2|
          if (d2 - d1).to_i == 1
            temp += 1
            longest = [longest, temp].max
          else
            temp = 1
          end
        end

        { current: current, longest: longest, active_days: active_days }
      end

      def self.build_hour_counts(sessions)
        counts = Hash.new(0)
        sessions.each do |s|
          counts[s[:started_at].hour] += 1
        end
        counts
      end

      def self.calculate_work_modes(tools)
        total = tools.size.to_f
        return { exploration: 0, building: 0, testing: 0 } if total.zero?

        result = {}
        WORK_MODE_TOOLS.each do |mode, mode_tools|
          count = tools.count { |t| mode_tools.include?(t) }
          result[mode] = (count / total * 100).round
        end
        result
      end

      def self.most_productive_day(daily)
        return nil if daily.empty?
        date, data = daily.max_by { |_, d| d[:sessions] }
        { date: date, sessions: data[:sessions], messages: data[:messages] }
      end

      def self.build_daily_cost(sessions)
        daily = Hash.new(0.0)
        sessions.each do |s|
          date = s[:started_at].to_date.to_s
          daily[date] += estimate_cost([s])
        end
        daily.sort.to_h
      end

      def self.build_hour_day_grid(sessions)
        # 7 rows (wday: 0=Sun..6=Sat) × 24 cols (hours)
        grid = Array.new(7) { Array.new(24, 0) }
        sessions.each do |s|
          grid[s[:started_at].wday][s[:started_at].hour] += 1
        end
        grid
      end

      def self.build_per_project(sessions)
        sessions.group_by { |s| s[:project] }.transform_values do |ss|
          {
            sessions:     ss.size,
            messages:     ss.sum { |s| s[:message_count] },
            tools:        ss.sum { |s| s[:tool_count] },
            last_active:  ss.map { |s| s[:ended_at] }.max,
            branches:     ss.map { |s| s[:git_branch] }.compact.uniq
          }
        end.sort_by { |_, v| -v[:sessions] }.to_h
      end

      def self.build_models_breakdown(sessions)
        models = sessions.map { |s| s[:model] }.compact
        total  = models.size.to_f
        return {} if total.zero?

        models.tally
              .sort_by { |_, c| -c }
              .to_h
              .transform_values { |c| { count: c, pct: (c / total * 100).round } }
      end

      def self.top_prompt_words(words)
        words.tally
             .reject { |w, _| STOPWORDS.include?(w) || w.length < 3 || w.match?(/^\d+$/) }
             .sort_by { |_, c| -c }
             .first(6)
             .to_h
      end

      def self.empty_metrics
        {
          total_sessions: 0, total_messages: 0, total_tool_calls: 0,
          total_input_tokens: 0, total_output_tokens: 0,
          total_cache_read: 0, total_cache_write: 0, hour_day_grid: Array.new(7) { Array.new(24, 0) },
          estimated_cost: 0.0, first_session: nil, projects: 0,
          project_names: [], most_active_project: nil,
          tool_counts: {}, top_tools: {}, favorite_tool: nil,
          daily_activity: {}, daily_cost: {}, streaks: { current: 0, longest: 0, active_days: 0 },
          hour_counts: {}, work_modes: { exploration: 0, building: 0, testing: 0 },
          longest_session: nil, most_messages_session: nil,
          most_productive_day: nil, busiest_hour: nil,
          models_used: [], models_breakdown: {},
          total_prompts: 0, avg_prompt_words: 0, top_prompt_words: {},
          per_project: {}
        }
      end
    end
  end
end
