---@class Image
---@field node any
---@field range {start_row: number, start_col: number, end_row: number, end_col: number}
---@field url string
---@field width? number
---@field height? number

---@param buffer? number
---@return Image[]
local get_buffer_images = function(buffer)
  local bufnr = buffer or vim.api.nvim_get_current_buf()

  local parser = vim.treesitter.get_parser(bufnr, "markdown_inline")
  local root = parser:parse()[1]:root()
  local query = vim.treesitter.query.parse("markdown_inline", "(image (link_destination) @url) @image")

  local images = {}
  local current_image = nil

  for id, node in query:iter_captures(root, 0) do
    local key = query.captures[id]
    local value = vim.treesitter.get_node_text(node, bufnr)

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

return {
  validate = function(bufnr)
    return vim.api.nvim_buf_get_option(bufnr, "filetype") == "markdown"
  end,
  get_buffer_images = get_buffer_images,
}
