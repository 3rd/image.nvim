local utils = require("image/utils")

local resolve_absolute_path = function(markdown_file_path, image_path)
  if string.sub(image_path, 1, 1) == "/" then return image_path end
  local markdown_dir = vim.fn.fnamemodify(markdown_file_path, ":h")
  local absolute_image_path = markdown_dir .. "/" .. image_path
  absolute_image_path = vim.fn.fnamemodify(absolute_image_path, ":p")
  return absolute_image_path
end

local is_remote_url = function(url)
  return string.sub(url, 1, 7) == "http://" or string.sub(url, 1, 8) == "https://"
end

---@return { node: any, range: { start_row: number, start_col: number, end_row: number, end_col: number }, url: string }[]
local query_buffer_images = function(buffer)
  local buf = buffer or vim.api.nvim_get_current_buf()

  local parser = vim.treesitter.get_parser(buf, "markdown_inline")
  local root = parser:parse()[1]:root()
  local query = vim.treesitter.query.parse("markdown_inline", "(image (link_destination) @url) @image")

  local images = {}
  local current_image = nil

  for id, node in query:iter_captures(root, 0) do
    local key = query.captures[id]
    local value = vim.treesitter.get_node_text(node, buf)

    if key == "image" then
      local start_row, start_col, end_row, end_col = node:range()
      current_image = {
        node = node,
        range = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
      }
    elseif key == "url" then
      current_image.url = value
      table.insert(images, current_image)
      current_image = nil
    end
  end

  return images
end

---@type fun(ctx: IntegrationContext)
local render = function(ctx)
  local windows = utils.window.get_visible_windows()

  for _, window in ipairs(windows) do
    if vim.bo[window.buffer].filetype == "markdown" then
      local matches = query_buffer_images(window.buffer)
      local lines = vim.api.nvim_buf_get_lines(window.buffer, 0, -1, false)

      local previous_images = ctx.api.get_images({
        window = window.id,
        buffer = window.buffer,
      })
      local new_image_ids = {}

      local file_path = vim.api.nvim_buf_get_name(window.buffer)

      for _, match in ipairs(matches) do
        local id = string.format("%d:%d:%d:%s", window.id, window.buffer, match.range.start_row, match.url)
        local height = nil

        ---@param image Image
        local render_image = function(image)
          if ctx.options.sizing_strategy == "height-from-empty-lines" then
            local empty_line_count = -1
            for i = match.range.end_row + 2, #lines do
              if lines[i] == "" then
                empty_line_count = empty_line_count + 1
              else
                break
              end
            end
            height = math.max(1, empty_line_count)
          end
          image.render({
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
      end

      for _, image in ipairs(previous_images) do
        if not vim.tbl_contains(new_image_ids, image.id) then image.clear() end
      end
    end
  end
end

---@type fun(ctx: IntegrationContext)
local setup_autocommands = function(ctx)
  local group = vim.api.nvim_create_augroup("image.nvim:markdown", { clear = true })

  vim.api.nvim_create_autocmd({
    "WinNew",
    "BufWinEnter",
    "WinResized",
  }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= "markdown" then return end
      render(ctx)
    end,
  })

  vim.api.nvim_create_autocmd({
    "TextChanged",
    "TextChangedI",
  }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype ~= "markdown" then return end
      render(ctx)
    end,
  })

  if ctx.options.clear_in_insert_mode then
    vim.api.nvim_create_autocmd({
      "InsertEnter",
    }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype ~= "markdown" then return end
        local current_window = vim.api.nvim_get_current_win()
        local images = ctx.api.get_images({ window = current_window })
        for _, image in ipairs(images) do
          image.clear()
        end
      end,
    })

    vim.api.nvim_create_autocmd({
      "InsertLeave",
    }, {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].filetype ~= "markdown" then return end
        render(ctx)
      end,
    })
  end
end

---@type fun(api: API, options: MarkdownIntegrationOptions)
local setup = function(api, options)
  local opts = options or {} --[[@as MarkdownIntegrationOptions]]
  local context = {
    api = api,
    options = opts,
  }

  vim.defer_fn(function()
    setup_autocommands(context)
    render(context)
  end, 0)
end

---@class MarkdownIntegration: Integration
local integration = {
  setup = setup,
}

return integration
