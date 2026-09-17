-- tests/export_spec.lua
describe("export", function()
  local export
  local tmp_dir

  local function stats(total_count, total_uniques, daily_breakdown)
    return {
      repo = "test/repo",
      metric = "clones",
      period_start = "2025-01-01",
      period_end = "2025-01-31",
      total_count = total_count,
      total_uniques = total_uniques,
      daily_breakdown = daily_breakdown,
    }
  end

  before_each(function()
    package.loaded["github_stats.export"] = nil
    export = require("github_stats.export")

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("directory auto-creation", function()
    it("creates a non-existent nested parent directory before writing CSV", function()
      local target = tmp_dir .. "/does/not/exist/yet/Clones.csv"
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(0, vim.fn.isdirectory(vim.fn.fnamemodify(target, ":h")))

      local daily = { ["2025-01-01"] = { count = 5, uniques = 2 } }
      local ok, err = export.export_daily_csv("test/repo", "clones", daily, target)

      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, vim.fn.filereadable(target))
    end)

    it("creates a non-existent nested parent directory before writing Markdown", function()
      local target = tmp_dir .. "/reports/2025/Clones.md"
      local ok, err =
        export.export_markdown("test/repo", "clones", stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }), target)

      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(1, vim.fn.filereadable(target))
    end)

    it("does not error when the parent directory already exists", function()
      vim.fn.mkdir(tmp_dir, "p")
      local target = tmp_dir .. "/existing.csv"
      local ok = export.export_daily_csv("test/repo", "clones", { ["2025-01-01"] = { count = 1, uniques = 1 } }, target)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok)
    end)
  end)

  describe("combined clones+views export", function()
    it("export_combined_csv merges both metrics into one row per date", function()
      local target = tmp_dir .. "/combined.csv"
      local clones_daily = { ["2025-01-01"] = { count = 10, uniques = 4 } }
      local views_daily = { ["2025-01-01"] = { count = 3, uniques = 1 }, ["2025-01-02"] = { count = 7, uniques = 2 } }

      local ok, err = export.export_combined_csv("test/repo", clones_daily, views_daily, target)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)

      local lines = vim.fn.readfile(target)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("repository,date,clones_count,clones_uniques,views_count,views_uniques", lines[1])
      -- Row for 2025-01-01 has both clones and views; 2025-01-02 has only views (clones default to 0)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("test/repo,2025-01-01,10,4,3,1", lines[2])
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("test/repo,2025-01-02,0,0,7,2", lines[3])
    end)

    it("export_combined_markdown includes totals for both metrics", function()
      local target = tmp_dir .. "/combined.md"
      local clones_stats = stats(10, 4, { ["2025-01-01"] = { count = 10, uniques = 4 } })
      local views_stats = stats(3, 1, { ["2025-01-01"] = { count = 3, uniques = 1 } })

      local ok, err = export.export_combined_markdown("test/repo", clones_stats, views_stats, target)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)

      local content = table.concat(vim.fn.readfile(target), "\n")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("Total Clones"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("Total Views"))
    end)

    it("export_combined_summary_markdown includes a Highlights section", function()
      local target = tmp_dir .. "/summary.md"
      local clones_results = { ["a/repo"] = stats(50, 20, { ["2025-01-01"] = { count = 50, uniques = 20 } }) }
      local views_results = { ["a/repo"] = stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }) }

      local ok, err = export.export_combined_summary_markdown(clones_results, views_results, target)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)

      local content = table.concat(vim.fn.readfile(target), "\n")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("## Highlights"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("Most cloned repository"))
    end)
  end)

  describe("export_summary_markdown Highlights section", function()
    it("names the top repo by total count", function()
      local target = tmp_dir .. "/summary.md"
      local results = {
        ["a/low"] = stats(10, 5, { ["2025-01-01"] = { count = 10, uniques = 5 } }),
        ["b/high"] = stats(100, 50, { ["2025-01-01"] = { count = 100, uniques = 50 } }),
      }

      local ok, err = export.export_summary_markdown("clones", results, target)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(ok, err)

      local content = table.concat(vim.fn.readfile(target), "\n")
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("## Highlights"))
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(content:find("b/high"))
    end)
  end)

  describe("PDF export via pdfport.nvim (optional dependency)", function()
    local function reset_pdfport()
      package.loaded["pdfport"] = nil
    end

    after_each(reset_pdfport)

    it("reports an error when pdfport.nvim is not installed", function()
      reset_pdfport()
      local got
      export.export_markdown_pdf(
        "test/repo",
        "clones",
        stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }),
        tmp_dir .. "/report.pdf",
        function(ok, err)
          got = { ok = ok, err = err }
        end
      )
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(got.ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(got.err:find("not installed"))
    end)

    it("reports an error when pdfport has no available markdown producer", function()
      package.loaded["pdfport"] = {
        create = function() end,
        can_create = function()
          return false
        end,
      }
      local got
      export.export_markdown_pdf(
        "test/repo",
        "clones",
        stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }),
        tmp_dir .. "/report.pdf",
        function(ok, err)
          got = { ok = ok, err = err }
        end
      )
      ---@diagnostic disable-next-line: undefined-field
      assert.is_false(got.ok)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(got.err:find("markdown producer"))
    end)

    it("passes the built Markdown report to pdfport.create() as text", function()
      local create_opts
      package.loaded["pdfport"] = {
        can_create = function(kind)
          return kind == "markdown"
        end,
        create = function(opts)
          create_opts = opts
          opts.__callback({ status = "ok", path = opts.output })
        end,
      }

      local target = tmp_dir .. "/report.pdf"
      local got
      export.export_markdown_pdf(
        "test/repo",
        "clones",
        stats(5, 2, { ["2025-01-01"] = { count = 5, uniques = 2 } }),
        target,
        function(ok, err)
          got = { ok = ok, err = err }
        end
      )

      ---@diagnostic disable-next-line: undefined-field
      assert.is_true(got.ok, got.err)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals("markdown", create_opts.from)
      ---@diagnostic disable-next-line: undefined-field
      assert.equals(vim.fn.expand(target), create_opts.output)
      ---@diagnostic disable-next-line: undefined-field
      assert.is_not_nil(create_opts.text:find("GitHub Stats Report: test/repo"))
    end)
  end)
end)

---@diagnostic disable: undefined-global

-- The rest of export.lua: the CSV writers' own shape, the Markdown report
-- bodies, the pdfport gate, and the failure each writer reports rather than
-- raising.
describe("export writers", function()
  local export
  local tmp_dir

  local function stats(daily_breakdown, overrides)
    return vim.tbl_extend("force", {
      repo = "test/repo",
      metric = "clones",
      period_start = "2025-01-01",
      period_end = "2025-01-31",
      total_count = 1234,
      total_uniques = 567,
      daily_breakdown = daily_breakdown,
    }, overrides or {})
  end

  ---Read a written export back as lines.
  ---@param path string
  ---@return string[]
  local function read_lines(path)
    return vim.fn.readfile(path)
  end

  before_each(function()
    package.loaded["github_stats.export"] = nil
    export = require("github_stats.export")

    tmp_dir = vim.fn.tempname()
    vim.fn.delete(tmp_dir, "rf")
    vim.fn.mkdir(tmp_dir, "p")
  end)

  after_each(function()
    vim.fn.delete(tmp_dir, "rf")
  end)

  describe("export_daily_csv", function()
    it("writes a header and one row per date, oldest first", function()
      local target = tmp_dir .. "/daily.csv"

      local ok = export.export_daily_csv("test/repo", "clones", {
        ["2025-01-02"] = { count = 2, uniques = 1 },
        ["2025-01-01"] = { count = 5, uniques = 3 },
      }, target)

      assert.is_true(ok)
      local lines = read_lines(target)
      assert.equals("repository,metric,date,count,uniques", lines[1])
      assert.equals("test/repo,clones,2025-01-01,5,3", lines[2])
      assert.equals("test/repo,clones,2025-01-02,2,1", lines[3])
    end)

    it("refuses to write an empty export", function()
      local ok, err = export.export_daily_csv("test/repo", "clones", {}, tmp_dir .. "/empty.csv")

      assert.is_false(ok)
      assert.equals("No data to export", err)
      assert.equals(0, vim.fn.filereadable(tmp_dir .. "/empty.csv"))
    end)

    it("quotes a field containing a comma or a quote", function()
      local target = tmp_dir .. "/escaped.csv"

      export.export_daily_csv('odd,"name"', "clones", { ["2025-01-01"] = { count = 1, uniques = 1 } }, target)

      local lines = read_lines(target)
      assert.is_truthy(lines[2]:find('"odd,""name"""', 1, true))
    end)
  end)

  describe("export_combined_csv", function()
    it("zero-fills a date only one metric knows about", function()
      local target = tmp_dir .. "/combined.csv"

      export.export_combined_csv(
        "test/repo",
        { ["2025-01-01"] = { count = 5, uniques = 3 } },
        { ["2025-01-02"] = { count = 9, uniques = 4 } },
        target
      )

      local lines = read_lines(target)
      assert.equals("repository,date,clones_count,clones_uniques,views_count,views_uniques", lines[1])
      assert.equals("test/repo,2025-01-01,5,3,0,0", lines[2])
      assert.equals("test/repo,2025-01-02,0,0,9,4", lines[3])
    end)

    it("refuses to write an empty export", function()
      local ok, err = export.export_combined_csv("test/repo", {}, {}, tmp_dir .. "/empty.csv")

      assert.is_false(ok)
      assert.equals("No data to export", err)
    end)
  end)

  describe("export_markdown", function()
    it("writes a report with a summary and a breakdown table", function()
      local target = tmp_dir .. "/report.md"

      export.export_markdown("test/repo", "clones", stats({ ["2025-01-01"] = { count = 1234, uniques = 567 } }), target)

      local text = table.concat(read_lines(target), "\n")
      assert.is_truthy(text:find("# GitHub Stats Report: test/repo", 1, true))
      assert.is_truthy(text:find("**Metric:** clones", 1, true))
      assert.is_truthy(text:find("**Period:** 2025-01-01 to 2025-01-31", 1, true))
      -- Thousands separators, in both the summary and the table.
      assert.is_truthy(text:find("**Total Count:** 1,234", 1, true))
      assert.is_truthy(text:find("| 2025-01-01 | 1,234 | 567 |", 1, true))
    end)

    it("still writes a report for a period with no days in it", function()
      local target = tmp_dir .. "/empty.md"

      local ok = export.export_markdown("test/repo", "clones", stats({}), target)

      assert.is_true(ok)
      assert.is_truthy(table.concat(read_lines(target), "\n"):find("| Date | Count | Uniques |", 1, true))
    end)
  end)

  describe("format_number", function()
    it("groups thousands and rounds a mean", function()
      assert.equals("1,234,567", export.format_number(1234567))
      assert.equals("0", export.format_number(0))
    end)
  end)

  describe("has_pdfport", function()
    it("is false when pdfport.nvim is not installed", function()
      local real = package.loaded["pdfport"]
      package.loaded["pdfport"] = nil
      package.preload["pdfport"] = nil

      assert.is_false(export.has_pdfport())

      package.loaded["pdfport"] = real
    end)

    it("is false when pdfport cannot produce Markdown", function()
      local real = package.loaded["pdfport"]
      package.loaded["pdfport"] = {
        can_create = function()
          return false
        end,
      }

      assert.is_false(export.has_pdfport())

      package.loaded["pdfport"] = real
    end)

    it("is true once pdfport reports a markdown producer", function()
      local real = package.loaded["pdfport"]
      package.loaded["pdfport"] = {
        can_create = function(kind)
          return kind == "markdown"
        end,
      }

      assert.is_true(export.has_pdfport())

      package.loaded["pdfport"] = real
    end)
  end)

  describe("write failures", function()
    -- BUG: write_lines() pcalls the writefile but not the mkdir that
    -- ensure_parent_dir() does first, so a parent directory that cannot be
    -- created (here: the path already exists as a file) escapes as a raw
    -- `E739: Cannot create directory` instead of the "Export failed: ..."
    -- message :GithubStats export promises -- the very kind of raw error
    -- ensure_parent_dir was added to stop leaking to the user. Pinned in its
    -- current shape rather than fixed.
    it("lets a parent directory it cannot create escape as a raw E739", function()
      local blocker = tmp_dir .. "/blocker"
      vim.fn.writefile({ "i am a file" }, blocker)

      local ok, err = pcall(
        export.export_daily_csv,
        "test/repo",
        "clones",
        { ["2025-01-01"] = { count = 1, uniques = 1 } },
        blocker .. "/nested.csv"
      )

      assert.is_false(ok)
      assert.is_truthy(tostring(err):find("E739", 1, true))
    end)

    it("reports an unwritable target path instead of raising", function()
      -- Parent exists, the file itself cannot be written (the target is a
      -- directory): this half is inside write_lines()' pcall and is reported.
      local ok, err = export.export_daily_csv("test/repo", "clones", { ["2025-01-01"] = { count = 1, uniques = 1 } }, tmp_dir)

      assert.is_false(ok)
      assert.is_truthy(err:find("Failed to write file", 1, true))
    end)
  end)
end)
