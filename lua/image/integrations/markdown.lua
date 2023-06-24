---@type Integration
local integration = {
  validate = function(buf)
    return vim.api.nvim_buf_get_option(buf, "filetype") == "markdown"
  end,

  get_buffer_images = function(buffer)
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
  end,
}

return integration
