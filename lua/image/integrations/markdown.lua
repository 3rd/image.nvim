local utils = require("image/utils")

local get_buffer_images = function(buffer)
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
  ctx.clear()

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  for _, window in ipairs(windows) do
    if vim.bo[window.buf].filetype == "markdown" then
      local images = get_buffer_images(window.buf)

      for _, image in ipairs(images) do
        -- local id = utils.random.id()
        local id = string.format("%d:%d:%d", window.id, window.buf, image.range.start_row)
        -- utils.log("rendering", id)

        local max_cols = window.width
        local max_rows = window.height

        if ctx.options.sizing_strategy == "height-from-empty-lines" then
          local empty_lines = -1
          for i = image.range.end_row + 2, #lines do
            if lines[i] == "" then
              empty_lines = empty_lines + 1
            else
              break
            end
          end
          max_rows = empty_lines
        end

        ctx.render_relative_to_window(
          window,
          id,
          image.url,
          image.range.start_col,
          image.range.start_row + 1,
          max_cols,
          max_rows
        )
      end
    end
  end
end

---@type fun(ctx: IntegrationContext)
local setup_autocommands = function(ctx)
  local events = {
    "BufEnter",
    "BufLeave",
    "TextChanged",
    "WinScrolled",
    "WinResized",
    "InsertEnter",
    "InsertLeave",
  }
  local group = vim.api.nvim_create_augroup("image.nvim:markdown", { clear = true })
  vim.api.nvim_create_autocmd(events, {
    group = group,
    callback = function(args)
      if args.event == "InsertEnter" then
        ctx.clear()
      else
        render(ctx)
      end
    end,
  })
end

---@type fun(ctx: IntegrationContext)
local setup = function(ctx)
  local options = ctx.options --[[@as MarkdownIntegrationOptions]]
  setup_autocommands(ctx)
  render(ctx)
end

---@class MarkdownIntegration: Integration
local integration = {
  setup = setup,
}

return integration
