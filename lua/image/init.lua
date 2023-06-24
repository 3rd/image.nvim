local utils = require("image/utils")

local default_options = {
  backend = "ueberzug",
  integrations = {
    markdown = {
      enabled = true,
    },
  },
  margin = {
    top = 0,
    right = 1,
    bottom = 1,
    left = 0,
  },
  -- sizing_strategy = "scale",
}

local state = {
  options = default_options,
  integrations = {},
  backend = nil,
}

---@class markdown_integration_options
---@field enabled boolean
---@class integrations
---@field markdown markdown_integration_options
---@class options
---@field backend "kitty"|"ueberzug"
---@field integrations integrations

local get_windows = function()
  local windows = {}
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buffer = vim.api.nvim_win_get_buf(window)
    local width = vim.api.nvim_win_get_width(window)
    local height = vim.api.nvim_win_get_height(window)
    local pos = vim.api.nvim_win_get_position(window)
    table.insert(windows, {
      winnr = window,
      bufnr = buffer,
      width = width,
      height = height,
      x = pos[2],
      y = pos[1],
    })
  end
  return windows
end

local rerender_integrations = function()
  local backend = state.backend
  local windows = get_windows()

  -- backend.clear()

  local x_offset = state.options.margin.left
  if vim.opt.number then
    local width = vim.opt.numberwidth:get()
    x_offset = x_offset + width
  end
  if vim.opt.signcolumn ~= "no" then x_offset = x_offset + 2 end
  x_offset = x_offset - vim.fn.col("w0")

  local y_offset = state.options.margin.top
  if vim.opt.showtabline == 2 then y_offset = y_offset + 1 end
  y_offset = y_offset - vim.fn.line("w0") + 1

  for _, window in ipairs(windows) do
    for _, integration in ipairs(state.integrations) do
      if integration.validate(window.bufnr) then
        local images = integration.get_buffer_images(window.bufnr)
        for _, image in ipairs(images) do
          -- log("render", image)
          local id = utils.nanoid()
          local width = vim.fn.min({
            image.width or 100,
            window.width - state.options.margin.left - state.options.margin.right - x_offset,
          })
          local height = vim.fn.min({ image.height or 100, window.height - state.options.margin.bottom - y_offset })
          local x = window.x + image.range.start_col + x_offset
          local y = window.y + image.range.start_row + 2 + y_offset
          backend.render(id, image.url, x, y, width, height)
        end
      end
    end
  end
end

local setup_autocommands = function()
  local events = {
    "BufEnter",
    "BufLeave",
    "TextChanged",
    "WinScrolled",
    "WinResized",
    "InsertEnter",
    "InsertLeave",
  }
  local group = vim.api.nvim_create_augroup("render", { clear = true })

  vim.api.nvim_create_autocmd(events, {
    group = group,
    callback = function(args)
      if args.event == "InsertEnter" then
        state.backend.clear()
      else
        rerender_integrations()
      end
    end,
  })
end

---@param options options
local setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})

  local ok, backend = pcall(require, "image/backends/" .. opts.backend)
  if not ok then
    vim.api.nvim_err_writeln("render: failed to load " .. opts.backend .. " backend")
    return
  end

  local integrations = {}
  for name, integration in pairs(opts.integrations) do
    if integration.enabled then
      ---@diagnostic disable-next-line: redefined-local
      local ok, integration_module = pcall(require, "image/integrations." .. name)
      if ok then
        table.insert(integrations, integration_module)
      else
        vim.api.nvim_err_writeln("render: failed to load" .. name .. " integration")
      end
    end
  end

  state = {
    options = opts,
    integrations = integrations,
    backend = backend,
  }

  setup_autocommands()
end

local render = function(id, url, x, y, width, height)
  if not state.backend then
    vim.api.nvim_err_writeln("render: could not resolve backend")
    return
  end
  state.backend.render(id, url, x, y, width, height)
end

local clear = function(id)
  if not state.backend then
    vim.api.nvim_err_writeln("render: could not resolve backend")
    return
  end
  state.backend.clear(id)
end

return {
  setup = setup,
  render = render,
  clear = clear,
}
