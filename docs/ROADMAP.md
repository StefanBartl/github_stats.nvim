# Roadmap

What's actually open, nothing else. The reasoning behind this list — findings,
alternatives, effort and risk per item — lives in
[`ROADMAP/KONZEPT.md`](ROADMAP/KONZEPT.md); speculative designs with no
decision behind them stay in [`ROADMAP/IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md).

| # | Item | Why | Concept |
|---|---|---|---|
| 1 | Dashboard auto-refresh | `dashboard.refresh_interval_seconds` is configured, validated, typed and documented, but no code ever starts the timer | [P0.1](ROADMAP/KONZEPT.md#1-dashboard-auto-refresh-gibt-es-nicht) |
| 2 | Specs for the render layer | `build_lines()`/`build_header()` and the line arithmetic are untested — where the last real bugs were | [P1.4](ROADMAP/KONZEPT.md#4-die-testabdeckung-endet-vor-der-darstellung) |
| 3 | Read memo for stored metrics | Every keypress re-reads and re-decodes the full history of every repo | [P1.2](ROADMAP/KONZEPT.md#2-jeder-tastendruck-liest-die-gesamte-historie-neu-von-der-platte) |
| 4 | Fixed trend window | The trend arrow halves whatever range is displayed, so `7d` and `max` show the same symbol for different things | [P1.3](ROADMAP/KONZEPT.md#3-der-trend-indikator-misst-etwas-anderes-als-der-nutzer-denkt) |
| 5 | Highlight groups | The dashboard sets no highlights at all; colour carries no information | [P2.5](ROADMAP/KONZEPT.md#5-das-dashboard-hat-keine-einzige-hervorhebung) |
| 6 | Sparkline per dashboard entry | `visualization.lua` can already draw them; the list view doesn't use them | [P2.6](ROADMAP/KONZEPT.md#6-sparklines-existieren-aber-nicht-dort-wo-man-sie-sucht) |
| 7 | Totals row across repositories | The most obvious question — overall trend — is the one the dashboard doesn't answer | [P2.7](ROADMAP/KONZEPT.md#7-keine-gesamtsumme-über-alle-repositories) |
| 8 | Calendar-accurate `Nm`/`Ny` | `3m`/`1y` are 30/365-day approximations next to calendar-exact date presets | [P3.8](ROADMAP/KONZEPT.md#8-3m-und-1y-sind-näherungen-this_month-ist-es-nicht) |

Order and rationale: see
[Empfohlene Reihenfolge](ROADMAP/KONZEPT.md#empfohlene-reihenfolge).

---
