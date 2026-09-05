# Export to CSV, Markdown, and PDF

- **Module:** `export.lua` (`export_daily_csv`, `export_markdown`, `export_summary_markdown`, `export_combined_*`, `has_pdfport`, `create_pdf`), `bindings/usrcmds/export.lua`
- **Usercmds:** `:GithubStats export {repo\|all} {clones\|views\|both} {filepath}`

Extension on `{filepath}` selects the format (`.csv`, `.md`, `.pdf`); a
missing extension defaults to `.md` for the `all` target (CSV doesn't
support multi-repo output) and `.csv` otherwise — an extension that's
present but *different* (e.g. `.txt`) is left alone and still errors rather
than being silently rewritten. Parent directories are created automatically.

PDF export routes through the optional
[`pdfport.nvim`](https://github.com/StefanBartl/pdfport.nvim) dependency
(`pcall`-guarded, `export.has_pdfport()`/`pdfport.can_create("markdown")`
checked first): the same lines the Markdown export would write are handed
to `pdfport.create()` directly, with no intermediate `.md` file. It is the
one asynchronous writer of the three, reported through a callback rather
than a return value. Without pdfport the export fails with a clear error
rather than silently downgrading to another format.

Every summary export (single-repo or `all`) includes a Highlights section
from `analytics.compute_highlights`. `all` + `both` produces one combined
summary carrying both clones and views highlights, rather than two separate
reports.
