# Known Bugs

None currently tracked.

## Resolved

## Dashboard

1. ~~Scrolling problem - last entry~~ — fixed: `dashboard/render.lua` now
   exports `M.ENTRY_LINES = 5` as the single source of truth for per-entry
   line height, and `dashboard/state.lua`/`dashboard/movement.lua` reference
   it instead of a hardcoded `6` (see
   [FEATURES.md](../FEATURES.md#rendering-one-source-of-truth-for-line-height)).

---
