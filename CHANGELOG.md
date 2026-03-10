# Changelog

All notable changes to this project will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-03-10

### Added
- Full-screen btop-style TUI dashboard
- Streaks: current, longest, active days
- Personal bests: longest session, most productive day, busiest hour, favorite tool
- Work mode breakdown: Explore / Build / Test
- Top tools ranked bar chart with gradient coloring
- Tokens & cost panel with per-model cost estimation
- Activity chart (last 30 days)
- Hourly heatmap (day × hour, shown on taller terminals)
- Time filters: Today / Week / Month / All Time (`t`/`w`/`m`/`a`)
- Per-project breakdown with git branch tracking
- `stats` command with `--today`, `--week`, `--month` flags
- `doctor` command to verify data sources
- Zero configuration — reads `~/.claude/` directly
