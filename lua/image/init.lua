local utils = require("image/utils")
local image = require("image/image")
local magick = require("image/magick")

---@type Options
local default_options = {
  -- backend = "ueberzug",
  backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
    },
    neorg = {
      enabled = true,
    },
    syslang = {
      enabled = true,
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  kitty_method = "normal",
  window_overlap_clear_enabled = false,
  window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
  editor_only_render_when_focused = false,
}

---@type State
local state = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  backend = nil,
  options = default_options,
  images = {},
  extmarks_namespace = vim.api.nvim_create_namespace("image.nvim"),
  remote_cache = {},
  tmp_dir = vim.fn.tempname(),
}

---@type API
---@diagnostic disable-next-line: missing-fields
local api = {}

---@param options Options
api.setup = function(options)
  local opts = vim.tbl_deep_extend("force", default_options, options or {})
  state.options = opts

  -- check that magick is available
  if not magick.has_magick then
    vim.api.nvim_err_writeln("image.nvim: magick rock not found, please install it and restart your editor")
    return
  end

  -- load backend
  local backend = require("image/backends/" .. opts.backend)
  if type(backend.setup) == "function" then backend.setup(state) end
  state.backend = backend

  -- load integrations
  for integration_name, integration_options in pairs(opts.integrations) do
    if integration_options.enabled then
      local integration = require("image/integrations/" .. integration_name)
      if type(integration.setup) == "function" then integration.setup(api, integration_options, state) end
    end
  end

  -- create tmp dir
  vim.fn.mkdir(state.tmp_dir, "p")

  -- handle folds / scroll extra
  ---@type table<number, { topline: number, botline: number, bufnr: number, height: number; folded_lines: number }>
  local window_history = {}
  vim.api.nvim_set_decoration_provider(state.extmarks_namespace, {
    on_win = vim.schedule_wrap(function(_, winid, bufnr, topline, botline)
      if not vim.api.nvim_win_is_valid(winid) then return false end
      if not vim.api.nvim_buf_is_valid(bufnr) then return false end

      -- get current window
      local window = nil
      local windows = {}
      if state.options.window_overlap_clear_enabled then
        windows = utils.window.get_windows({
          normal = true,
          floating = true,
          with_masks = state.options.window_overlap_clear_enabled,
          ignore_masking_filetypes = state.options.window_overlap_clear_ft_ignore,
        })
        for _, w in ipairs(windows) do
          if w.id == winid then
            window = w
            break
          end
        end
      else
        window = utils.window.get_window(winid)
      end

      -- utils.debug("on_win", { winid = winid, bufnr = bufnr })
      if not window then return false end

      -- toggle images in overlapped windows
      if state.options.window_overlap_clear_enabled then
        for _, current_window in ipairs(windows) do
          local images = api.get_images({ window = current_window.id, buffer = bufnr })
          if #current_window.masks > 0 then
            for _, current_image in ipairs(images) do
              current_image:clear(true)
            end
          else
            for _, current_image in ipairs(images) do
              current_image:render()
            end
          end
        end
      end

      -- all handling below is only for non-floating windows
      if window.is_floating then return false end

      -- get history entry or init
      local prev = window_history[winid]
      if not prev then
        -- new window, rerender all existing images
        local images = api.get_images()
        for _, current_image in ipairs(images) do
          current_image:render()
        end
        window_history[winid] = { topline = topline, botline = botline, bufnr = bufnr }
        return false
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
      -- utils.debug("needs_clear", needs_clear, "needs_rerender", needs_rerender)
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

      return false
    end),
  })

  -- setup autocommands
  local group = vim.api.nvim_create_augroup("image.nvim", { clear = true })

  -- auto-clear on window close
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function() -- auto-clear images when windows and buffers change
      vim.schedule(function()
        local images = api.get_images()
        for _, current_image in ipairs(images) do
          local ok, is_valid = pcall(vim.api.nvim_win_is_valid, current_image.window)
          if not ok then return end
          if is_valid then
            current_image:render()
          else
            current_image:clear()
          end
        end
      end)
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

  -- auto-toggle on editor focus change
  if state.options.editor_only_render_when_focused then
    local images_to_restore_on_focus = {}
    vim.api.nvim_create_autocmd("FocusLost", {
      group = group,
      callback = function() -- auto-clear images when windows and buffers change
        vim.schedule(function()
          local images = api.get_images()
          for _, current_image in ipairs(images) do
            if current_image.is_rendered then
              table.insert(images_to_restore_on_focus, current_image)
              current_image:clear(true)
            end
          end
        end)
      end,
    })
    vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      callback = function() -- auto-clear images when windows and buffers change
        vim.schedule(function()
          for _, current_image in ipairs(images_to_restore_on_focus) do
            current_image:render()
          end
          images_to_restore_on_focus = {}
        end)
      end,
    })
  end
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
