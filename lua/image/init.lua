local utils = require("image/utils")

---@type Options
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
}

---@type State
local state = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  backend = nil,
  integrations = {},
  options = default_options,
}

---@param image_id string
---@param url string
---@param x number
---@param y number
---@param max_width number
---@param max_height number
local render = function(image_id, url, x, y, max_width, max_height)
  if not state.backend then utils.throw("render: could not resolve backend") end
  state.backend.render(image_id, url, x, y, max_width, max_height)
end

---@param win Window
---@param image_id string
---@param url string
---@param x number
---@param y number
---@param max_width number
---@param max_height number
---@return boolean
local render_relative_to_window = function(win, image_id, url, x, y, max_width, max_height)
  if not state.backend then utils.throw("render: could not resolve backend") end
  if not utils.window.is_window_visible(win) then return false end

  local relative_rect = utils.render.relate_rect_to_window(win, x, y, max_width, max_height)

  if relative_rect.is_visible then
    state.backend.render(
      image_id,
      url,
      relative_rect.x,
      relative_rect.y,
      relative_rect.max_width,
      relative_rect.max_height
    )
    return true
  else
    return false
  end
end

local clear = function(id)
  if not state.backend then utils.throw("render: could not resolve backend") end
  state.backend.clear(id)
end

----------------------------------------------------------------------------------
local rerender_integrations = function()
  local backend = state.backend
  local windows = utils.window.get_visible_windows()
  backend.clear()
  for _, window in ipairs(windows) do
    for _, integration in ipairs(state.integrations) do
      if integration.validate(window.buf) then
        local images = integration.get_buffer_images(window.buf)
        for _, image in ipairs(images) do
          local id = utils.random.id()
          render_relative_to_window(window, id, image.url, image.range.start_col, image.range.start_row + 1, 100, 100)
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
----------------------------------------------------------------------------------

---@param options Options
local setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})

  -- load backend
  local backend_ok, backend = pcall(require, "image/backends/" .. opts.backend)
  if not backend_ok then
    utils.throw("render: failed to load " .. opts.backend .. " backend")
    return
  end
  if type(backend.setup) == "function" then backend.setup() end

  -- load integrations
  local integrations = {}
  for name, integration in pairs(opts.integrations) do
    if integration.enabled then
      local integration_ok, integration_module = pcall(require, "image/integrations." .. name)
      if integration_ok then
        table.insert(integrations, integration_module)
      else
        utils.throw("render: failed to load " .. name .. " integration")
      end
    end
  end

  -- setup
  state = {
    options = opts,
    integrations = integrations,
    backend = backend,
  }
  setup_autocommands()
end

return {
  setup = setup,
  render = render,
  clear = clear,
}
