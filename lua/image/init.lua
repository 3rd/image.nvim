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

---@param win Window|number
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

---@param options Options
local setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})

  -- load backend
  local backend_ok, backend = pcall(require, "image/backends/" .. opts.backend)
  if not backend_ok then
    utils.throw("render: failed to load " .. opts.backend .. " backend")
    return
  end
  if type(backend.setup) == "function" then backend.setup(options) end

  -- set state
  state = {
    options = opts,
    backend = backend,
  }

  -- load integrations
  for name, integration_options in pairs(opts.integrations) do
    if integration_options.enabled then
      local integration_ok, integration = pcall(require, "image/integrations." .. name)
      if not integration_ok then utils.throw("render: failed to load " .. name .. " integration") end
      if type(integration.setup) == "function" then
        integration.setup({
          options = integration_options,
          render = render,
          render_relative_to_window = render_relative_to_window,
          clear = clear,
        })
      end
    end
  end
end

return {
  setup = setup,
  render = render,
  clear = clear,
}
