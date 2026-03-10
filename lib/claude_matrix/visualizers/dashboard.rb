require "tty-screen"
require "pastel"

module ClaudeMatrix
  module Visualizers
    class Dashboard
      CONTENT = :content
      DIVIDER = :divider

      DAY_NAMES = %w[Mon Tue Wed Thu Fri Sat Sun].freeze
      DAY_WDAY  = [1, 2, 3, 4, 5, 6, 0].freeze

      FILTER_LABELS = {
        today: "Today",
        week:  "Week",
        month: "Month",
        all:   "All Time"
      }.freeze

      def initialize(metrics, filter: :all)
        @m      = metrics
        @filter = filter
        @p      = Pastel.new
        @w      = TTY::Screen.width
        @h      = TTY::Screen.height
        # Content area: full height minus top(1) + header(1) + sep(1) + footer-sep(1) + footer(1) + bottom(1) = 6
        @content_h = [@h - 6, 10].max
        # Column widths
        @lw = [(@w * 0.33).to_i, 28].max.clamp(28, 40)
        @rw = @w - @lw - 3  # 3 = left│ + divider│ + right│
        # Allocate right-column section heights
        @n_tools, @act_h, @show_heatmap = allocate_right(@m[:top_tools].to_a.size)
      end

      # Returns the rendered string — exactly @h lines, no trailing newline
      def render
        left_rows  = build_left
        right_rows = build_right

        left_rows.shift  while left_rows.first&.dig(:type) == DIVIDER
        right_rows.shift while right_rows.first&.dig(:type) == DIVIDER

        left_rows  = fit(left_rows,  @content_h, @lw)
        right_rows = fit(right_rows, @content_h, @rw)

        out = []
        out << top_border
        out << header_line
        out << dim("├" + "─" * @lw + "┬" + "─" * @rw + "┤")
        @content_h.times { |i| out << merge_row(left_rows[i], right_rows[i]) }
        out << dim("├" + "─" * (@w - 2) + "┤")
        out << filter_bar
        out << dim("└" + "─" * (@w - 2) + "┘")

        # Join without trailing newline — prevents terminal scroll
        print out.join("\n")
      end

      private

      # ── Height allocation ──────────────────────────────────────────────────

      def allocate_right(n_avail)
        # Each right section costs: 1 divider + 1 title (except first section, divider stripped)
        # Always show: Tools + Tokens(3 rows) + Activity
        # Optionally: Heatmap (1 title + 8 content = 9)
        tokens_rows = 3
        heatmap_rows = 9   # title(1) + hour-header(1) + 7 days
        # Fixed cost (sections×2 overhead, tokens content, minus 1 because first divider stripped)
        fixed_3sec = 3 * 2 - 1 + tokens_rows    # = 8
        fixed_4sec = 4 * 2 - 1 + tokens_rows + heatmap_rows  # = 19

        pool3 = @content_h - fixed_3sec
        pool4 = @content_h - fixed_4sec

        if pool4 >= 5  # enough for tools(min 2) + activity(min 3)
          n_tools   = [n_avail, [(pool4 * 0.50).to_i, 2].max, 10].min
          act_h     = [pool4 - n_tools, 3].max
          [n_tools, act_h, true]
        else
          n_tools   = [n_avail, [(pool3 * 0.55).to_i, 2].max, 10].min
          act_h     = [pool3 - n_tools, 3].max
          [n_tools, act_h, false]
        end
      end

      # ── Borders ────────────────────────────────────────────────────────────

      def top_border
        filter_pill = " ◄ #{FILTER_LABELS[@filter]} ► "
        title  = " Claude Matrix "
        ver    = " v1.0 "
        fill   = [@w - 2 - vis(title) - vis(ver) - vis(filter_pill), 0].max
        dim("┌") +
          bold(bright_cyan(title)) +
          dim("─" * (fill / 2)) +
          bright_yellow(filter_pill) +
          dim("─" * (fill - fill / 2)) +
          dim(ver) +
          dim("┐")
      end

      def header_line
        s = @m[:streaks]
        badge = s[:current] >= 7 ? " 🔥" : s[:current] >= 3 ? " ⚡" : ""
        cost  = @m[:estimated_cost]
        cost_s = "$#{"%.2f" % cost}"

        parts = [
          "#{dim('Sessions')} #{bright_cyan(@m[:total_sessions].to_s)}",
          "#{dim('Messages')} #{bright_cyan(fmt(@m[:total_messages]))}",
          "#{dim('In')} #{green(fmt(@m[:total_input_tokens]))}  #{dim('Out')} #{bright_yellow(fmt(@m[:total_output_tokens]))}",
          "#{dim('Cost')} #{cost_color(cost, cost_s)}",
          "#{dim('Streak')} #{streak_color(s[:current], "#{s[:current]}d#{badge}")}",
          "#{dim('Since')} #{dim(@m[:first_session]&.strftime('%b %Y') || '—')}",
        ]

        # Build greedily — drop rightmost parts that don't fit
        line = "  "
        parts.each do |p|
          candidate = line == "  " ? "  #{p}" : "#{line}   #{p}"
          break if vis(candidate) > @w - 2
          line = candidate
        end
        dim("│") + pad(line, @w - 2) + dim("│")
      end

      def filter_bar
        tabs = FILTER_LABELS.map do |f, label|
          key = f.to_s[0].upcase
          if f == @filter
            " " + bold(bright_white("[#{key}]#{label}")) + " "
          else
            " " + dim("[#{key}]") + dim(label) + " "
          end
        end.join(dim("│"))

        right_keys = dim("  r") + dim(":refresh  ") + dim("q") + dim(":quit  ")
        fill = [@w - 2 - vis(tabs) - vis(right_keys) - 2, 0].max
        dim("│") + " " + tabs + " " * fill + right_keys + dim("│")
      end

      # ── Row renderer ──────────────────────────────────────────────────────

      def merge_row(lr, rr)
        ld = lr[:type] == DIVIDER
        rd = rr[:type] == DIVIDER
        if    ld && rd then dim("├" + "─" * @lw + "┼" + "─" * @rw + "┤")
        elsif ld        then dim("├" + "─" * @lw + "┤") + rr[:text] + dim("│")
        elsif rd        then dim("│") + lr[:text] + dim("├" + "─" * @rw + "┤")
        else                 dim("│") + lr[:text] + dim("│") + rr[:text] + dim("│")
        end
      end

      # ── Left column ───────────────────────────────────────────────────────

      def build_left
        s    = @m[:streaks]
        ls   = @m[:longest_session]
        mpd  = @m[:most_productive_day]
        wm   = @m[:work_modes]
        bw   = [@lw - 17, 1].max

        rows = []
        rows += section("STREAKS", @lw, [
          kv("Current",  streak_color(s[:current], "#{s[:current]} days") + (s[:current] >= 7 ? "  🔥" : s[:current] >= 3 ? "  ⚡" : ""), @lw),
          kv("Longest",  bright_cyan("#{s[:longest]} days"), @lw),
          kv("Active",   dim("#{s[:active_days]} days"), @lw),
        ])

        rows += section("PERSONAL BESTS", @lw, [
          kv("Longest",  ls  ? green(format_dur(ls[:duration_secs]))                      : dim("—"), @lw),
          kv("Best Day", mpd ? bright_cyan("#{mpd[:date]}") + dim(" (#{mpd[:sessions]}s)") : dim("—"), @lw),
          kv("Busiest",  @m[:busiest_hour] ? bright_cyan("%02d:00" % @m[:busiest_hour])    : dim("—"), @lw),
          kv("Top Tool", @m[:favorite_tool] ? green(@m[:favorite_tool][0,10]) + dim(" (#{@m[:tool_counts][@m[:favorite_tool]]})") : dim("—"), @lw),
        ])

        rows += section("WORK MODE", @lw, [
          wbar("Explore", wm[:exploration], :cyan,   bw),
          wbar("Build",   wm[:building],    :green,  bw),
          wbar("Test",    wm[:testing],     :yellow, bw),
        ])

        name_w   = [(@lw * 0.38).to_i, 8].max
        time_w   = 7
        branch_w = [@lw - name_w - 2 - 4 - 2 - time_w - 2, 0].max

        proj_lines = @m[:per_project].map do |proj, d|
          last   = d[:last_active] ? time_ago(d[:last_active]) : "—"
          branch = d[:branches].first
          binfo  = branch_w > 2 && branch ? dim("[#{branch[0, branch_w]}]") : ""
          "  #{bright_cyan(proj[0, name_w].ljust(name_w))} #{dim(d[:sessions].to_s.rjust(2) + 's')}  #{dim(last.ljust(time_w))} #{binfo}"
        end
        rows += section("PROJECTS", @lw, proj_lines)
        rows
      end

      # ── Right column ──────────────────────────────────────────────────────

      def build_right
        rows = []
        rows += section("TOP TOOLS", @rw, tool_lines)
        rows += section("TOKENS & COST", @rw, token_lines)
        rows += section("ACTIVITY  (last 30 days)", @rw, activity_lines)
        rows += section("HEATMAP  day × hour", @rw, heatmap_lines) if @show_heatmap
        rows
      end

      # ── Section helper ────────────────────────────────────────────────────

      def section(title, w, lines)
        [divr,
         cr(sec_title(title, w), w)] + lines.map { |l| cr(l, w) }
      end

      def sec_title(title, w)
        fill = [w - vis(title) - 2, 0].max
        " #{bold(bright_cyan(title))} #{dim("─" * fill)}"
      end

      # ── Tool bars ─────────────────────────────────────────────────────────

      def tool_lines
        tools = @m[:top_tools].to_a
        return [ind("No data yet")] if tools.empty?

        max_cnt = tools.first.last.to_f
        cnt_w   = tools.first.last.to_s.length
        bar_w   = [@rw - 20 - cnt_w, 4].max

        tools.first(@n_tools).map do |tool, count|
          ratio   = count.to_f / max_cnt
          bw      = [(ratio * bar_w).round, 1].max
          # Color gradient: high→bright_cyan, mid→cyan, low→blue
          bar_col = ratio > 0.7 ? method(:bright_cyan) : ratio > 0.35 ? method(:cyan) : method(:blue)
          bar     = bar_col.call("█" * bw) + dim("░" * [bar_w - bw, 0].max)
          cnt_s   = bright_white(count.to_s.rjust(cnt_w))
          "  #{dim(tool[0, 14].ljust(14))} #{bar}  #{cnt_s}"
        end
      end

      # ── Token / Cost bars ─────────────────────────────────────────────────

      def token_lines
        total_in  = @m[:total_input_tokens]
        total_out = @m[:total_output_tokens]
        total_io  = total_in + total_out
        return [ind("No token data")] if total_io.zero?

        bar_w = [@rw - 24, 4].max
        cost  = @m[:estimated_cost]

        in_pct   = (100.0 * total_in  / total_io).round
        out_pct  = 100 - in_pct
        in_bw    = [(in_pct  * bar_w / 100.0).round, 1].max
        out_bw   = [(out_pct * bar_w / 100.0).round, 1].max

        in_bar  = green("█" * in_bw)  + dim("░" * [bar_w - in_bw, 0].max)
        out_bar = bright_yellow("█" * out_bw) + dim("░" * [bar_w - out_bw, 0].max)

        cache_eff = total_in > 0 ? (@m[:total_cache_read].to_f / total_in).round(1) : 0
        cache_s   = @m[:total_cache_read] > 0 ? "  #{dim("cache")} #{bright_cyan(fmt(@m[:total_cache_read]))} #{dim("(#{cache_eff}× eff)")}" : ""

        [
          "  #{green('In ')}  #{green(fmt(total_in).rjust(7))}  #{in_bar}  #{dim("#{in_pct}%")}",
          "  #{bright_yellow('Out')}  #{bright_yellow(fmt(total_out).rjust(7))}  #{out_bar}  #{dim("#{out_pct}%")}",
          "  #{dim('Est. Cost')}  #{bold(cost_color(cost, "$#{"%.2f" % cost}"))}#{cache_s}",
        ]
      end

      # ── Activity chart ────────────────────────────────────────────────────

      def activity_lines
        daily = @m[:daily_activity]
        return [ind("No session data")] if daily.empty?

        last30   = daily.to_a.last(30)
        max_sess = [last30.map { |_, d| d[:sessions] }.max, 1].max.to_f
        max_cols = [(@rw - 6) / 2, last30.size].min
        cols     = last30.last(max_cols)
        n        = cols.size
        bar_h    = [@act_h - 1, 2].max

        grid = Array.new(bar_h) { Array.new(n, "  ") }
        cols.each_with_index do |(_, data), ci|
          ratio = data[:sessions].to_f / max_sess
          h     = (ratio * bar_h).round
          cell  = ratio > 0.75 ? bright_green("██") :
                  ratio > 0.40 ? green("██") :
                  ratio > 0.0  ? cyan("▓▓") : "  "
          h.times { |r| grid[bar_h - 1 - r][ci] = cell }
        end

        peak  = last30.map { |_, d| d[:sessions] }.max
        lines = grid.each_with_index.map do |row, r|
          suffix = r == 0 ? "  #{dim(peak.to_s)}" : ""
          "  " + row.join + suffix
        end

        axis = Array.new(n * 2 + 10, " ")
        [28, 21, 14, 7, 0].each do |ago|
          ci = n - 1 - ago; next if ci < 0 || ci >= n
          lbl = ago == 0 ? "today" : "#{ago}d"
          lbl.chars.each_with_index { |c, li| axis[ci * 2 + li] = c if ci * 2 + li < axis.size }
        end
        "today".chars.each_with_index { |c, li| axis[(n-1)*2+li] = c } if axis.all?(" ")
        lines << "  " + dim(axis.join.rstrip)
        lines
      end

      # ── Heatmap ───────────────────────────────────────────────────────────

      def heatmap_lines
        grid    = @m[:hour_day_grid]
        max_val = [grid.flatten.max, 1].max.to_f
        step    = 3
        hlabels = (0..21).step(step).map { |h| h.to_s.rjust(3) }.join
        lines   = ["  #{dim("     #{hlabels}")}"]
        DAY_WDAY.each_with_index do |wday, i|
          cells = (0..21).step(step).map { |h| heat_block(grid[wday][h], max_val) }.join("  ")
          lines << "  #{cyan(DAY_NAMES[i])}  #{cells}"
        end
        lines
      end

      def heat_block(count, max)
        r = count.to_f / max
        if    r == 0   then dim("░")
        elsif r < 0.33 then blue("▒")
        elsif r < 0.66 then cyan("▓")
        else                bright_green("█")
        end
      end

      # ── Work mode bars ────────────────────────────────────────────────────

      def wbar(label, pct, color, bw)
        bw      = [bw, 1].max
        filled  = [(pct.to_f / 100 * bw).round, 0].max
        empty   = [bw - filled, 0].max
        bar     = @p.send(color, "█" * filled) + dim("░" * empty)
        pct_s   = @p.send(color, "#{pct}%".rjust(4))
        "  #{label.ljust(7)} #{pct_s}  #{bar}"
      end

      # ── Row primitives ────────────────────────────────────────────────────

      def cr(text, width)
        { type: CONTENT, text: pad(text, width) }
      end

      def divr
        { type: DIVIDER }
      end

      def fit(rows, target, width)
        blank = cr("", width)
        rows  = rows.first(target) if rows.size > target
        rows += Array.new([target - rows.size, 0].max, blank)
        rows
      end

      # ── Text helpers ──────────────────────────────────────────────────────

      def kv(key, value_s, width)
        overhead = 13  # "  " + key.ljust(9) + "  " = 2+9+2
        max_vw   = width - overhead
        val_s    = vis(value_s) > max_vw ? plain_truncate(value_s, max_vw) : value_s
        "  #{dim(key.ljust(9))}  #{val_s}"
      end

      def ind(text)
        "  #{dim(text)}"
      end

      def pad(text, width)
        len = vis(text)
        return plain_truncate(text, width) if len > width
        text + " " * (width - len)
      end

      def plain_truncate(text, max)
        # Measure visible length of text; if exceeds max, cut plain text
        plain = strip_ansi(text)
        return text if plain.length <= max
        plain[0, max - 1] + "…"
      end

      def vis(s)
        strip_ansi(s).length
      end

      def strip_ansi(s)
        s.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")
         .gsub(/[\u{1F300}-\u{1FFFF}]|[\u{2600}-\u{27BF}]|[\u{FE00}-\u{FE0F}]/, "XX")
         .gsub(/[^\x00-\x7F]/, "X")
      end

      def fmt(n)
        return "0" unless n && n > 0
        n >= 1_000_000 ? "%.1fM" % (n / 1_000_000.0) :
        n >= 1_000     ? "%.1fK" % (n / 1_000.0) : n.to_s
      end

      def format_dur(secs)
        return "—" unless secs && secs > 0
        h = secs / 3600; m = (secs % 3600) / 60
        h > 0 ? "#{h}h #{m}m" : "#{m}m"
      end

      def time_ago(t)
        return "—" unless t
        diff = Time.now - t
        case diff
        when 0..60         then "now"
        when 61..3600      then "#{(diff / 60).to_i}m ago"
        when 3601..86400   then "#{(diff / 3600).to_i}h ago"
        when 86401..604800 then "#{(diff / 86400).to_i}d ago"
        else t.strftime("%b %-d")
        end
      end

      def cost_color(cost, text)
        if cost >= 10.0 then @p.bold.bright_red(text)
        elsif cost >= 3.0 then @p.yellow(text)
        else @p.green(text)
        end
      end

      def streak_color(n, text)
        if    n >= 14 then @p.bold.bright_red(text)
        elsif n >= 7  then @p.bold.bright_yellow(text)
        elsif n >= 3  then @p.yellow(text)
        elsif n >= 1  then @p.cyan(text)
        else               dim(text)
        end
      end

      # ── Color aliases ─────────────────────────────────────────────────────

      def bold(s)          = @p.bold(s)
      def dim(s)           = @p.dim(s)
      def cyan(s)          = @p.cyan(s)
      def bright_cyan(s)   = @p.bright_cyan(s)
      def green(s)         = @p.green(s)
      def bright_green(s)  = @p.bright_green(s)
      def yellow(s)        = @p.yellow(s)
      def bright_yellow(s) = @p.bright_yellow(s)
      def blue(s)          = @p.blue(s)
      def bright_white(s)  = @p.bright_white(s)
    end
  end
end
