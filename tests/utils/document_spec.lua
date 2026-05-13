local unload_document_modules = function()
  package.loaded["image/utils/document"] = nil
  package.loaded["image/utils/render_scheduler"] = nil
end

local make_match = function(row, url)
  return {
    node = {},
    range = {
      start_row = row,
      start_col = 0,
      end_row = row,
      end_col = 1,
    },
    url = url,
  }
end

describe("document integration rendering", function()
  local originals
  local buffer
  local autocmds
  local utils
  local changedtick
  local from_file_calls
  local from_url_calls
  local render_calls
  local clear_calls
  local previous_images

  before_each(function()
    unload_document_modules()
    buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].filetype = "markdown"
    changedtick = 1
    autocmds = {}
    from_file_calls = {}
    from_url_calls = {}
    render_calls = {}
    clear_calls = {}
    previous_images = {}
    utils = require("image/utils")

    originals = {
      schedule = vim.schedule,
      create_augroup = vim.api.nvim_create_augroup,
      create_autocmd = vim.api.nvim_create_autocmd,
      buf_attach = vim.api.nvim_buf_attach,
      win_is_valid = vim.api.nvim_win_is_valid,
      win_get_buf = vim.api.nvim_win_get_buf,
      win_get_cursor = vim.api.nvim_win_get_cursor,
      buf_get_name = vim.api.nvim_buf_get_name,
      buf_get_changedtick = vim.api.nvim_buf_get_changedtick,
      get_windows = utils.window.get_windows,
      get_window = utils.window.get_window,
    }

    vim.schedule = function(callback)
      callback()
    end
    vim.api.nvim_create_augroup = function()
      return 1
    end
    vim.api.nvim_create_autocmd = function(events, opts)
      if type(events) ~= "table" then events = { events } end
      for _, event in ipairs(events) do
        autocmds[event] = autocmds[event] or {}
        table.insert(autocmds[event], opts.callback)
      end
    end
    vim.api.nvim_buf_attach = function()
      return true
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_win_get_buf = function()
      return buffer
    end
    vim.api.nvim_win_get_cursor = function()
      return { 1, 0 }
    end
    vim.api.nvim_buf_get_name = function()
      return "/tmp/document.md"
    end
    vim.api.nvim_buf_get_changedtick = function()
      return changedtick
    end
    utils.window.get_windows = function()
      return {
        {
          id = 1,
          buffer = buffer,
          buffer_filetype = "markdown",
          height = 10,
          scroll_y = 0,
        },
      }
    end
    utils.window.get_window = function()
      return {
        id = 1,
        buffer = buffer,
        buffer_filetype = "markdown",
        height = 10,
        scroll_y = 0,
      }
    end
  end)

  after_each(function()
    vim.schedule = originals.schedule
    vim.api.nvim_create_augroup = originals.create_augroup
    vim.api.nvim_create_autocmd = originals.create_autocmd
    vim.api.nvim_buf_attach = originals.buf_attach
    vim.api.nvim_win_is_valid = originals.win_is_valid
    vim.api.nvim_win_get_buf = originals.win_get_buf
    vim.api.nvim_win_get_cursor = originals.win_get_cursor
    vim.api.nvim_buf_get_name = originals.buf_get_name
    vim.api.nvim_buf_get_changedtick = originals.buf_get_changedtick
    utils.window.get_windows = originals.get_windows
    utils.window.get_window = originals.get_window
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
    unload_document_modules()
  end)

  local run_event = function(event, args)
    for _, callback in ipairs(autocmds[event] or {}) do
      callback(args)
    end
  end

  local setup_integration = function(query_buffer_images)
    local document = require("image/utils/document")
    local integration = document.create_document_integration({
      name = "test",
      default_options = {
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        only_render_image_at_cursor_mode = "popup",
        floating_windows = false,
        filetypes = { "markdown" },
      },
      query_buffer_images = query_buffer_images,
    })

    integration.setup({
      get_images = function()
        return previous_images
      end,
      from_file = function(path, opts)
        table.insert(from_file_calls, { path = path, opts = opts })
        return {
          id = opts.id,
          image_width = 10,
          image_height = 10,
          render = function(_, geometry)
            table.insert(render_calls, { id = opts.id, geometry = geometry })
          end,
        }
      end,
      from_url = function(url, opts, callback)
        table.insert(from_url_calls, { url = url, opts = opts, callback = callback })
      end,
    }, {}, {
      enabled = true,
      options = {
        max_height_window_percentage = 0,
      },
    })
  end

  it("reuses cached matches until changedtick changes", function()
    local query_count = 0
    setup_integration(function()
      query_count = query_count + 1
      return { make_match(2, "visible.png") }
    end)

    assert.are.same(1, query_count)

    run_event("WinScrolled", { file = "1" })
    assert.are.same(1, query_count)

    changedtick = 2
    run_event("WinScrolled", { file = "1" })
    assert.are.same(2, query_count)
  end)

  it("creates images only for viewport matches and clears stale images by id set", function()
    previous_images = {
      {
        id = "stale",
        clear = function()
          clear_calls[#clear_calls + 1] = "stale"
        end,
      },
    }

    setup_integration(function()
      return {
        make_match(2, "visible.png"),
        make_match(50, "offscreen.png"),
      }
    end)

    assert.are.same(1, #from_file_calls)
    assert.are.same("/tmp/visible.png", from_file_calls[1].path)
    assert.are.same({ "stale" }, clear_calls)
  end)

  it("does not render stale remote callbacks after the match leaves the viewport", function()
    local matches = { make_match(2, "https://example.test/image.png") }
    setup_integration(function()
      return matches
    end)

    assert.are.same(1, #from_url_calls)

    matches = {}
    changedtick = 2
    run_event("WinScrolled", { file = "1" })

    from_url_calls[1].callback({
      id = from_url_calls[1].opts.id,
      render = function()
        render_calls[#render_calls + 1] = "remote"
      end,
    })

    assert.are.same({}, render_calls)
  end)
end)
