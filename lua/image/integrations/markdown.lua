local utils = require("image/utils")

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

      for _, match in ipairs(matches) do
        local ok = pcall(utils.png.get_dimensions, match.url)
        if ok then
          local id = string.format("%d:%d:%d", window.id, window.buffer, match.range.start_row)
          local height = nil

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

          local image = ctx.api.from_file(match.url, {
            id = id,
            height = height,
            x = match.range.start_col,
            y = match.range.start_row + 1,
            window = window.id,
            buffer = window.buffer,
            with_virtual_padding = true,
          })
          image.render()

          table.insert(new_image_ids, id)
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
      local current_window = vim.api.nvim_get_current_win()
      local images = ctx.api.get_images({ window = current_window })
      for _, image in ipairs(images) do
        image.clear()
      end
      render(ctx)
    end,
  })
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
