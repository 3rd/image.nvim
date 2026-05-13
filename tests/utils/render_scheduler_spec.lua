local unload_scheduler = function()
  package.loaded["image/utils/render_scheduler"] = nil
end

describe("render scheduler", function()
  local original_schedule

  before_each(function()
    unload_scheduler()
    original_schedule = vim.schedule
  end)

  after_each(function()
    vim.schedule = original_schedule
    unload_scheduler()
  end)

  it("coalesces callbacks by key and runs the latest callback", function()
    local scheduled = {}
    vim.schedule = function(callback)
      scheduled[#scheduled + 1] = callback
    end

    local scheduler = require("image/utils/render_scheduler")
    local calls = {}

    scheduler.schedule("window:1", function()
      calls[#calls + 1] = "first"
    end)
    scheduler.schedule("window:1", function()
      calls[#calls + 1] = "second"
    end)
    scheduler.schedule("window:2", function()
      calls[#calls + 1] = "other"
    end)

    assert.are.same(2, #scheduled)

    scheduled[1]()
    scheduled[2]()

    assert.are.same({ "second", "other" }, calls)
  end)
end)
