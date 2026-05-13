---@diagnostic disable: duplicate-doc-field
local logger = require("image/utils/logger")
local render_scheduler = require("image/utils/render_scheduler")
local utils = require("image/utils")

local popup_window = nil

local resolve_absolute_path = function(document_file_path, image_path)
  if string.sub(image_path, 1, 1) == "/" then return image_path end
  if string.sub(image_path, 1, 1) == "~" then return vim.fn.fnamemodify(image_path, ":p") end
  local document_dir = vim.fn.fnamemodify(document_file_path, ":h")
  local absolute_image_path = document_dir .. "/" .. image_path
  absolute_image_path = vim.fn.fnamemodify(absolute_image_path, ":p")
  return absolute_image_path
end

local resolve_base64_image = function(document_file_path, image_path)
  local tmp_b64_path = vim.fn.tempname()
  local base64_part = image_path:gsub("^data:image/[%w%+]+;base64,", "")
  local decoded = vim.base64.decode(base64_part)

  local file = io.open(tmp_b64_path, "wb")
  if file ~= nil then
    file:write(decoded)
    file:close()
  end

  return tmp_b64_path
end

local is_remote_url = function(url)
  return string.sub(url, 1, 7) == "http://" or string.sub(url, 1, 8) == "https://"
end

---@param ctx IntegrationContext
---@param filetype string
---@return boolean
local has_valid_filetype = function(ctx, filetype)
  return vim.tbl_contains(ctx.options.filetypes or {}, filetype)
end

---@class DocumentIntegrationConfig
---@field name string
---@field query_buffer_images fun(buffer: number): { node: any, range: { start_row: number, start_col: number, end_row: number, end_col: number }, url: string }[]
---@field cache_key? fun(buffer: number, filetype: string): string
---@field disable_cache? boolean
---@field default_options? DocumentIntegrationOptions
---@field debug? boolean

---@param config DocumentIntegrationConfig
local create_document_integration = function(config)
  local log = logger.within("integration." .. config.name)

  local match_cache = {}
  local remote_request_tokens = {}
  local next_remote_request_token = 0

  local get_image_id = function(window, match)
    return string.format("%d:%d:%d:%s", window.id, window.buffer, match.range.start_row, utils.hash.sha256(match.url))
  end

  local get_cache_key = function(buffer, filetype)
    if config.cache_key then return config.cache_key(buffer, filetype) end
    return ("%s:%d:%s"):format(config.name, buffer, filetype)
  end

  local get_changedtick = function(buffer)
    local ok, changedtick = pcall(vim.api.nvim_buf_get_changedtick, buffer)
    if ok then return changedtick end
    return -1
  end

  local get_matches = function(buffer, filetype)
    if config.disable_cache then return config.query_buffer_images(buffer) end

    local changedtick = get_changedtick(buffer)
    local cache_key = get_cache_key(buffer, filetype)
    local cached = match_cache[cache_key]
    if cached and cached.changedtick == changedtick and cached.filetype == filetype then return cached.matches end

    log.debug("Querying buffer images", { buffer = buffer, filetype = filetype })
    local matches = config.query_buffer_images(buffer)
    match_cache[cache_key] = {
      changedtick = changedtick,
      filetype = filetype,
      matches = matches,
    }
    log.debug("Found matches", { count = #matches })
    return matches
  end

  local get_viewport_overscan = function(ctx, window)
    local percentage = ctx.state.options.max_height_window_percentage or 0
    return math.max(1, math.ceil(window.height * percentage / 100))
  end

  local is_match_in_viewport = function(ctx, window, match)
    local overscan = get_viewport_overscan(ctx, window)
    local top = (window.scroll_y or 0) - overscan
    local bottom = (window.scroll_y or 0) + window.height + overscan
    return match.range.end_row >= top and match.range.start_row <= bottom
  end

  local should_render_match = function(ctx, window, match, cursor_row)
    if ctx.options.only_render_image_at_cursor then return match.range.start_row == cursor_row end
    return is_match_in_viewport(ctx, window, match)
  end

  local image_id_belongs_to_window = function(id, window)
    local prefix = ("%d:%d:"):format(window.id, window.buffer)
    return string.sub(id, 1, #prefix) == prefix
  end

  local invalidate_stale_remote_requests = function(window, visible_image_ids)
    for id in pairs(remote_request_tokens) do
      if image_id_belongs_to_window(id, window) and not visible_image_ids[id] then remote_request_tokens[id] = nil end
    end
  end

  local set_remote_request = function(id)
    next_remote_request_token = next_remote_request_token + 1
    remote_request_tokens[id] = next_remote_request_token
    return next_remote_request_token
  end

  local is_current_remote_request = function(ctx, item, token)
    if remote_request_tokens[item.id] ~= token then return false end
    if not vim.api.nvim_win_is_valid(item.window.id) then return false end
    if vim.api.nvim_win_get_buf(item.window.id) ~= item.window.buffer then return false end

    local window = utils.window.get_window(item.window.id, { with_scroll = true })
    if not window then return false end

    local cursor_row = item.cursor_row
    if ctx.options.only_render_image_at_cursor then cursor_row = vim.api.nvim_win_get_cursor(item.window.id)[1] - 1 end
    return should_render_match(ctx, window, item.match, cursor_row)
  end

  local render_popup_image = function(image)
    if popup_window ~= nil then return end

    local term_size = utils.term.get_size()
    if not term_size then return end
    local width, height = utils.math.adjust_to_aspect_ratio(
      term_size,
      image.image_width,
      image.image_height,
      math.floor(term_size.screen_cols / 2),
      0
    )
    local win_config = {
      relative = "cursor",
      row = 1,
      col = 0,
      width = width,
      height = height,
      style = "minimal",
      border = "single",
    }
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "image_nvim_popup"
    local win = vim.api.nvim_open_win(buf, false, win_config)
    popup_window = win

    image.ignore_global_max_size = true
    image.window = win
    image.buffer = buf

    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        local win_info = vim.fn.getwininfo(win)[1]
        if win_info and win_info.wincol > 0 then
          image:render({
            x = 0,
            y = 0,
            width = width,
            height = height,
          })
        end
      end
    end, 10)
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      callback = function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        image:clear()
        popup_window = nil
      end,
      once = true,
    })
  end

  local render_image = function(ctx, item, image)
    log.debug("render_image called", { id = image.id })
    if ctx.options.only_render_image_at_cursor and ctx.options.only_render_image_at_cursor_mode == "popup" then
      render_popup_image(image)
      return
    end

    image:render({
      x = item.match.range.start_col,
      y = item.match.range.start_row,
    })
  end

  local process_image_queue = function(ctx, image_queue)
    log.debug("Processing image queue", { count = #image_queue })
    for _, item in ipairs(image_queue) do
      local is_popup = ctx.options.only_render_image_at_cursor
        and ctx.options.only_render_image_at_cursor_mode == "popup"

      if is_remote_url(item.match.url) then
        if ctx.options.download_remote_images then
          local request_token = set_remote_request(item.id)
          local ok = pcall(ctx.api.from_url, item.match.url, {
            id = item.id,
            window = item.window.id,
            buffer = item.window.buffer,
            with_virtual_padding = not is_popup,
            namespace = config.name,
          }, function(image)
            if not image then return end
            if not is_current_remote_request(ctx, item, request_token) then return end
            render_image(ctx, item, image)
          end)
          if not ok then remote_request_tokens[item.id] = nil end
        end
      else
        local path
        if ctx.options.resolve_image_path then
          path = ctx.options.resolve_image_path(item.file_path, item.match.url, resolve_absolute_path)
        elseif string.sub(item.match.url, 1, 10) == "data:image" then
          path = resolve_base64_image(item.file_path, item.match.url)
        else
          path = resolve_absolute_path(item.file_path, item.match.url)
        end

        log.debug("Creating image from file", { path_type = type(path), path_string = tostring(path), id = item.id })
        local ok, image = pcall(ctx.api.from_file, path, {
          id = item.id,
          window = item.window.id,
          buffer = item.window.buffer,
          with_virtual_padding = not is_popup,
          namespace = config.name,
        })
        if ok and image then
          log.debug("Image created successfully", { id = item.id })
          render_image(ctx, item, image)
        else
          log.debug("Failed to create image", { id = item.id, error = image })
        end
      end
    end
  end

  local render = function(ctx, target_window, target_buffer)
    if not ctx.state.enabled then return end

    local windows = utils.window.get_windows({
      normal = true,
      floating = ctx.options.floating_windows,
      with_scroll = not ctx.options.only_render_image_at_cursor,
    })
    local image_queue = {}

    for _, window in ipairs(windows) do
      if target_window and window.id ~= target_window then goto continue_window end
      if target_buffer and window.buffer ~= target_buffer then goto continue_window end
      if not has_valid_filetype(ctx, window.buffer_filetype) then goto continue_window end

      local matches = get_matches(window.buffer, window.buffer_filetype)
      local previous_images = ctx.api.get_images({
        window = window.id,
        buffer = window.buffer,
        namespace = config.name,
      })
      local matched_image_ids = {}
      local visible_image_ids = {}
      local file_path = vim.api.nvim_buf_get_name(window.buffer)
      local cursor = vim.api.nvim_win_get_cursor(window.id)
      local cursor_row = cursor[1] - 1

      for _, match in ipairs(matches) do
        local id = get_image_id(window, match)
        matched_image_ids[id] = true
        if not should_render_match(ctx, window, match, cursor_row) then goto continue_match end

        visible_image_ids[id] = true
        table.insert(image_queue, {
          id = id,
          match = match,
          window = window,
          file_path = file_path,
          cursor_row = cursor_row,
        })
        log.debug("Adding image to queue", { id = id, url = match.url })

        ::continue_match::
      end

      local retained_image_ids = ctx.options.only_render_image_at_cursor and visible_image_ids or matched_image_ids
      invalidate_stale_remote_requests(window, retained_image_ids)
      for _, image in ipairs(previous_images) do
        if not retained_image_ids[image.id] then image:clear() end
      end

      ::continue_window::
    end

    process_image_queue(ctx, image_queue)
  end

  local schedule_render = function(ctx, scope, target_window, target_buffer)
    render_scheduler.schedule(("document:%s:%s"):format(config.name, scope), function()
      render(ctx, target_window, target_buffer)
    end)
  end

  local schedule_integration_render = function(ctx)
    schedule_render(ctx, "integration", nil, nil)
  end

  local schedule_buffer_render = function(ctx, buffer)
    schedule_render(ctx, ("buffer:%d"):format(buffer), nil, buffer)
  end

  local schedule_window_render = function(ctx, window)
    schedule_render(ctx, ("window:%d"):format(window), window, nil)
  end

  local text_change_watched_buffers = {}
  local setup_text_change_watcher = function(ctx, buffer)
    if text_change_watched_buffers[buffer] then return end
    vim.api.nvim_buf_attach(buffer, false, {
      on_lines = function()
        schedule_buffer_render(ctx, buffer)
      end,
    })
    text_change_watched_buffers[buffer] = true
  end

  ---@type fun(ctx: IntegrationContext)
  local setup_autocommands = function(ctx)
    local group_name = ("image.nvim:%s"):format(config.name)
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })

    -- watch for window changes
    vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter", "BufEnter", "TabEnter" }, {
      group = group,
      callback = function(args)
        local buffer = args.buf or vim.api.nvim_get_current_buf()
        if not has_valid_filetype(ctx, vim.bo[buffer].filetype) then return end
        schedule_buffer_render(ctx, buffer)
      end,
    })

    vim.api.nvim_create_autocmd({ "WinScrolled" }, {
      group = group,
      callback = function(args)
        local window = tonumber(args.file)
        if not window or not vim.api.nvim_win_is_valid(window) then return end

        local buffer = vim.api.nvim_win_get_buf(window)
        if not has_valid_filetype(ctx, vim.bo[buffer].filetype) then return end
        schedule_window_render(ctx, window)
      end,
    })

    -- watch for text changes
    vim.api.nvim_create_autocmd({ "BufAdd", "BufNew", "BufNewFile", "BufWinEnter" }, {
      group = group,
      callback = function(args)
        if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
        setup_text_change_watcher(ctx, args.buf)
        schedule_buffer_render(ctx, args.buf)
      end,
    })
    if has_valid_filetype(ctx, vim.bo.filetype) then setup_text_change_watcher(ctx, vim.api.nvim_get_current_buf()) end

    if ctx.options.only_render_image_at_cursor then
      vim.api.nvim_create_autocmd({ "CursorMoved" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          schedule_window_render(ctx, vim.api.nvim_get_current_win())
        end,
      })
    end

    if ctx.options.clear_in_insert_mode then
      vim.api.nvim_create_autocmd({ "InsertEnter" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          local current_window = vim.api.nvim_get_current_win()
          local images = ctx.api.get_images({ window = current_window, namespace = config.name })
          for _, image in ipairs(images) do
            image:clear()
          end
        end,
      })

      vim.api.nvim_create_autocmd({ "InsertLeave" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          schedule_buffer_render(ctx, args.buf)
        end,
      })
    end
  end

  ---@type fun(api: API, options: IntegrationOptions, state: State)
  local setup = function(api, options, state)
    ---@diagnostic disable-next-line: missing-fields
    local opts = vim.tbl_deep_extend("force", config.default_options or {}, options or {})
    local context = {
      api = api,
      options = opts,
      state = state,
    }

    vim.schedule(function()
      setup_autocommands(context)
      schedule_integration_render(context)
    end)
  end

  return { setup = setup }
end

return {
  create_document_integration = create_document_integration,
}
