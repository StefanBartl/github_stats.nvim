# Roadmap

What's actually open, nothing else.

**Nothing is open right now.** Every item this file carried has shipped: the
eight findings from [`ROADMAP/KONZEPT.md`](ROADMAP/KONZEPT.md), each marked
there with what was actually built and why.

| Item | Concept |
|---|---|
| Dashboard auto-refresh -- the timer nothing ever started | P0.1 |
| Specs for the render layer | P1.4 |
| Read memo for stored metrics | P1.2 |
| Fixed trend window | P1.3 |
| Highlight groups | P2.5 |
| Sparkline per dashboard entry | P2.6 |
| Totals line across repositories | P2.7 |
| Calendar-accurate `Nm`/`Ny` | P3.8 |

Two further fixes fell out of the work rather than out of the concept:
`:checkhealth` rejected `refresh_interval_seconds = 0`, the very value the
docs give as the off switch; and the header and each entry's `Period:` line
claimed a period for repositories that had never been fetched. Both are in
[`devs/CHANGELOG.md`](devs/CHANGELOG.md).

Adding the next item means writing down what is actually wrong first --
[`ROADMAP/KONZEPT.md`](ROADMAP/KONZEPT.md) is the shape that takes: a finding
in the current source, alternatives weighed against each other, effort and
risk per item. Speculative designs with no decision behind them stay in
[`ROADMAP/IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md);
[`FEATURES.md`](FEATURES.md) remains the authoritative list of what exists.

---

## `docs/ROADMAP/` — design notes, audits, concepts

Everything below lives in [`docs/ROADMAP/`](ROADMAP/) and is **not** open work
unless it says so. Indexed here because a folder next to a file is easy to
miss, and these are the documents that explain *why* the plugin is shaped the
way it is.

| Document | What it is |
| --- | --- |
| [`Arch&Coding.md`](ROADMAP/Arch&Coding.md) | Architecture and coding rules, applied to this plugin. |
| [`Checklist.md`](ROADMAP/Checklist.md) | The PR/architecture checklist, applied to this plugin. |
| [`Zentral-Prinzipien.md`](ROADMAP/Zentral-Prinzipien.md) | The central principles, applied to this plugin. |
| [`KONZEPT.md`](ROADMAP/KONZEPT.md) | Concept: what would make github_stats.nvim better. |
| [`IDEAS/IDEAS.md`](ROADMAP/IDEAS/IDEAS.md) | Loose ideas, not costed. |

The audits share a convention: **✅ good · 🟡 partial · ❌ gap**.
Findings that were acted on are removed rather than ticked, so what is left
standing is either an open gap or a deliberate deviation with its reasoning.
