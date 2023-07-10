local utils = require("image/utils")
local image = require("image/image")

---@type Options
local default_options = {
  -- backend = "ueberzug",
  backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
      sizing_strategy = "auto",
      download_remote_images = true,
      clear_in_insert_mode = false,
    },
    neorg = {
      enabled = true,
      download_remote_images = true,
      clear_in_insert_mode = false,
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  kitty_method = "normal",
  kitty_tmux_write_delay = 10,
}

---@type State
local state = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  backend = nil,
  options = default_options,
  images = {},
  extmarks_namespace = nil,
  remote_cache = {},
  tmp_dir = vim.fn.tempname(),
}

---@type API
local api = {}

---@param options Options
api.setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})
  state.options = opts

  -- load backend
  local backend = require("image/backends/" .. opts.backend)
  if type(backend.setup) == "function" then backend.setup(state) end
  state.backend = backend

  -- load integrations
  for integration_name, integration_options in pairs(opts.integrations) do
    if integration_options.enabled then
      local integration = require("image/integrations/" .. integration_name)
      if type(integration.setup) == "function" then integration.setup(api, integration_options) end
    end
  end

  -- create tmp dir
  vim.fn.mkdir(state.tmp_dir, "p")

  -- setup namespaces
  state.extmarks_namespace = vim.api.nvim_create_namespace("image.nvim")

  -- handle folds / scroll extra
  ---@type table<number, { topline: number, botline: number, bufnr: number, height: number; folded_lines: number }>
  local window_history = {}
  vim.api.nvim_set_decoration_provider(state.extmarks_namespace, {
    on_win = function(_, winid, bufnr, topline, botline)
      -- utils.debug("on_win", { winid = winid })

      local prev = window_history[winid]
      if not prev then
        window_history[winid] = { topline = topline, botline = botline, bufnr = bufnr }
        return
      end

      local height = vim.api.nvim_win_get_height(winid)
      local needs_clear = false
      local needs_rerender = false

      -- clear if buffer changed
      needs_clear = prev.bufnr ~= bufnr

      -- rerender if height, topline, or botline changed
      needs_rerender = prev.topline ~= topline or prev.botline ~= botline or prev.height ~= height

      -- rerender if the amount of folded lines changed
      local folded_lines = 0
      local i = 1
      while i < botline do
        local fold_start, fold_end = vim.fn.foldclosed(i), vim.fn.foldclosedend(i)
        if fold_start ~= -1 and fold_end ~= -1 then
          folded_lines = folded_lines + (fold_end - fold_start)
          i = fold_end + 1
        else
          i = i + 1
        end
      end
      if prev.folded_lines ~= folded_lines then needs_rerender = true end

      -- store new state
      window_history[winid] =
        { topline = topline, botline = botline, bufnr = bufnr, height = height, folded_lines = folded_lines }

      -- execute deferred clear / rerender
      utils.debug("needs_clear", needs_clear, "needs_rerender", needs_rerender)
      if needs_rerender then utils.debug("window", winid, "needs rerender") end
      local images = (needs_clear and api.get_images({ window = winid, buffer = prev.bufnr }))
        or (needs_rerender and api.get_images({ window = winid, buffer = bufnr }))
        or {}
      vim.defer_fn(function()
        if needs_clear then
          for _, curr in ipairs(images) do
            curr:clear(true)
          end
        else
          for _, curr in ipairs(images) do
            curr:render()
          end
        end
      end, 0)
    end,
  })

  -- setup autocommands
  local group = vim.api.nvim_create_augroup("image.nvim", { clear = true })

  -- auto-clear on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(au) -- auto-clear images when windows and buffers change
      local images = api.get_images({ window = tonumber(au.file) })
      for _, current_image in ipairs(images) do
        current_image:clear()
      end
    end,
  })

  -- rerender on scroll
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function(au)
      local images = api.get_images({ window = tonumber(au.file) })
      for _, current_image in ipairs(images) do
        current_image:render()
      end
    end,
  })
end

local guard_setup = function()
  if not state.backend then utils.throw("image.nvim is not setup. Call setup() first.") end
end

---@param path string
---@param options? ImageOptions
api.from_file = function(path, options)
  guard_setup()
  return image.from_file(path, options, state)
end

---@param url string
---@param options? ImageOptions
---@param callback fun(image: Image|nil)
api.from_url = function(url, options, callback)
  guard_setup()
  image.from_url(url, options, callback, state)
end

---@param id? string
api.clear = function(id)
  guard_setup()
  local target = state.images[id]
  if target then
    target:clear()
  else
    state.backend.clear(id)
  end
end

---@param opts? { window?: number, buffer?: number }
---@return Image[]
api.get_images = function(opts)
  local images = {}
  for _, current_image in pairs(state.images) do
    if
      (opts and opts.window and opts.window == current_image.window and not opts.buffer)
      or (opts and opts.window and opts.window == current_image.window and opts.buffer and opts.buffer == current_image.buffer)
      or not opts
    then
      table.insert(images, current_image)
    end
  end
  return images
end

return api
