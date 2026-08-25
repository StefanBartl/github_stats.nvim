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
