local unload_window = function()
  package.loaded["image/utils/window"] = nil
end

describe("window metadata", function()
  local originals
  local buffer

  before_each(function()
    unload_window()
    buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].filetype = "markdown"
    originals = {
      tabpage_list_wins = vim.api.nvim_tabpage_list_wins,
      win_get_buf = vim.api.nvim_win_get_buf,
      win_get_width = vim.api.nvim_win_get_width,
      win_get_height = vim.api.nvim_win_get_height,
      win_get_position = vim.api.nvim_win_get_position,
      win_get_config = vim.api.nvim_win_get_config,
      getbufinfo = vim.fn.getbufinfo,
      win_execute = vim.fn.win_execute,
    }
  end)

  after_each(function()
    vim.api.nvim_tabpage_list_wins = originals.tabpage_list_wins
    vim.api.nvim_win_get_buf = originals.win_get_buf
    vim.api.nvim_win_get_width = originals.win_get_width
    vim.api.nvim_win_get_height = originals.win_get_height
    vim.api.nvim_win_get_position = originals.win_get_position
    vim.api.nvim_win_get_config = originals.win_get_config
    vim.fn.getbufinfo = originals.getbufinfo
    vim.fn.win_execute = originals.win_execute
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
    unload_window()
  end)

  local stub_single_window = function()
    vim.api.nvim_tabpage_list_wins = function()
      return { 1 }
    end
    vim.api.nvim_win_get_buf = function()
      return buffer
    end
    vim.api.nvim_win_get_width = function()
      return 80
    end
    vim.api.nvim_win_get_height = function()
      return 20
    end
    vim.api.nvim_win_get_position = function()
      return { 0, 0 }
    end
    vim.api.nvim_win_get_config = function()
      return { relative = "" }
    end
    vim.fn.getbufinfo = function()
      return { { listed = 1 } }
    end
  end

  it("skips scroll row lookup unless requested", function()
    stub_single_window()
    local calls = 0
    vim.fn.win_execute = function()
      calls = calls + 1
      return "6"
    end

    local window = require("image/utils/window")

    local cheap_windows = window.get_windows({ normal = true })
    assert.are.same(0, calls)
    assert.are.same(0, cheap_windows[1].scroll_y)

    local scrolled_windows = window.get_windows({ normal = true, with_scroll = true })
    assert.are.same(1, calls)
    assert.are.same(5, scrolled_windows[1].scroll_y)
  end)
end)
