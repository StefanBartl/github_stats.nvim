# Configuration

Everything about getting GitHub Stats configured, in the order you need it.
Start at [PREPARATION.md](PREPARATION.md) if you do not have a token yet,
otherwise at [INTRO.md](INTRO.md).

| Page | Answers |
| --- | --- |
| [PREPARATION.md](PREPARATION.md) | Creating a GitHub token, verifying `curl`, and testing that the token really reaches the traffic API |
| [INTRO.md](INTRO.md) | Every configuration option with its type and default, the two ways to set them, token management, and storage paths |
| [OPTION-A.md](OPTION-A.md) | The `setup()` route in full: worked examples, dynamic repository lists, per-machine conditionals, and migrating away from `config.json` |
| [OPTION-B.md](OPTION-B.md) | The `config.json` route in full: file structure, syncing it across machines, and validating it |
| [USER-DEFINED-DATE-PRESETS.md](USER-DEFINED-DATE-PRESETS.md) | The built-in date ranges and how to write your own preset functions |

Option A and Option B are not alternatives you have to choose between —
they can be combined, and when they are, `setup()` wins over `config.json`
key by key. [INTRO.md](INTRO.md#why-two-configuration-methods) explains why
both exist.

Dashboard configuration has its own page: [dashboard.md](../dashboard.md).
