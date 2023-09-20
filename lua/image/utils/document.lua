local utils = require("image/utils")

local resolve_absolute_path = function(document_file_path, image_path)
  if string.sub(image_path, 1, 1) == "/" then return image_path end
  if string.sub(image_path, 1, 1) == "~" then return vim.fn.fnamemodify(image_path, ":p") end
  local document_dir = vim.fn.fnamemodify(document_file_path, ":h")
  local absolute_image_path = document_dir .. "/" .. image_path
  absolute_image_path = vim.fn.fnamemodify(absolute_image_path, ":p")
  return absolute_image_path
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
---@field default_options? DocumentIntegrationOptions
---@field debug? boolean

---@param config DocumentIntegrationConfig
local create_document_integration = function(config)
  local trace = function(...)
    if config.debug then utils.log("[" .. config.name .. "]", ...) end
  end

  local render = vim.schedule_wrap(
    ---@param ctx IntegrationContext
    function(ctx)
      local windows = utils.window.get_windows({
        normal = true,
        with_masks = ctx.state.options.window_overlap_clear_enabled,
        ignore_masking_filetypes = ctx.state.options.window_overlap_clear_ft_ignore,
      })

      for _, window in ipairs(windows) do
        if has_valid_filetype(ctx, window.buffer_filetype) then
          local matches = config.query_buffer_images(window.buffer)

          local previous_images = ctx.api.get_images({
            window = window.id,
            buffer = window.buffer,
          })
          local new_image_ids = {}

          local file_path = vim.api.nvim_buf_get_name(window.buffer)
          local cursor_row = vim.api.nvim_win_get_cursor(window.id)

          for _, match in ipairs(matches) do
            local id = string.format("%d:%d:%d:%s", window.id, window.buffer, match.range.start_row, match.url)
            local height = nil

            if ctx.options.only_render_image_at_cursor then
              if match.range.start_row ~= cursor_row[1] - 1 then goto continue end
            end

            ---@param image Image
            local render_image = function(image)
              trace("rendering image %s at x=%d y=%d", match.url, match.range.start_col, match.range.start_row + 1)

              image:render({
                height = height,
                x = match.range.start_col,
                y = match.range.start_row + 1,
              })
              table.insert(new_image_ids, id)
            end

            -- remote
            if is_remote_url(match.url) then
              if not ctx.options.download_remote_images then return end

              ctx.api.from_url(
                match.url,
                { id = id, window = window.id, buffer = window.buffer, with_virtual_padding = true },
                function(image)
                  if not image then return end
                  render_image(image)
                end
              )
            else
              -- local
              local path = resolve_absolute_path(file_path, match.url)
              local ok, image = pcall(ctx.api.from_file, path, {
                id = id,
                window = window.id,
                buffer = window.buffer,
                with_virtual_padding = true,
              })
              if ok then render_image(image) end
            end

            ::continue::
          end

          -- clear previous images
          for _, image in ipairs(previous_images) do
            if not vim.tbl_contains(new_image_ids, image.id) then image:clear() end
          end
        end
      end
    end
  )

  ---@type fun(ctx: IntegrationContext)
  local setup_autocommands = function(ctx)
    local group_name = ("image.nvim:%s"):format(config.name)
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })

    vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter", "WinResized" }, {
      group = group,
      callback = function(args)
        if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
        render(ctx)
      end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = group,
      callback = function(args)
        if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
        if args.event == "TextChangedI" and ctx.options.clear_in_insert_mode then return end
        render(ctx)
      end,
    })

    if ctx.options.only_render_image_at_cursor then
      vim.api.nvim_create_autocmd({ "CursorMoved" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          render(ctx)
        end,
      })
    end

    if ctx.options.clear_in_insert_mode then
      vim.api.nvim_create_autocmd({ "InsertEnter" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          local current_window = vim.api.nvim_get_current_win()
          local images = ctx.api.get_images({ window = current_window })
          for _, image in ipairs(images) do
            image:clear()
          end
        end,
      })

      vim.api.nvim_create_autocmd({ "InsertLeave" }, {
        group = group,
        callback = function(args)
          if not has_valid_filetype(ctx, vim.bo[args.buf].filetype) then return end
          render(ctx)
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

    vim.defer_fn(function()
      setup_autocommands(context)
      render(context)
    end, 0)
  end

  return { setup = setup }
end

return {
  create_document_integration = create_document_integration,
}
