local document = require("image/utils/document")
local magic = require("image/utils/magic")

return document.create_document_integration({
  name = "org",
  default_options = {
    clear_in_insert_mode = false,
    download_remote_images = true,
    only_render_image_at_cursor = false,
    only_render_image_at_cursor_mode = "popup",
    floating_windows = false,
    filetypes = { "org" },
  },
  query_buffer_images = function(buffer)
    local bufnr = buffer or vim.api.nvim_get_current_buf()

    local parser = vim.treesitter.get_parser(bufnr, 'org')
    local root = parser:parse()[1]:root()

    local images = {}
    local query = vim.treesitter.query.parse('org', [[
      (link_desc url: (expr) @image_link)
      (link url: (expr) @image_link)
    ]])

    for _, node in query:iter_captures(root, bufnr) do
      local text = vim.treesitter.get_node_text(node, bufnr)
      if text then
        local relpath = vim.fn.expand(text:gsub("^file:", ""))
        local srcfile_abspath = vim.api.nvim_buf_get_name(0)
        local base_dir = vim.fn.fnamemodify(srcfile_abspath, ":h")
        local abspath = vim.fn.fnamemodify(base_dir .. "/" .. relpath, ":p")
        if magic.is_image(abspath) then
          local start_row, start_col, end_row, end_col = node:range()
          table.insert(
            images,
            {
              node = node,
              range = {
                start_row = start_row,
                start_col = start_col,
                end_row = end_row,
                end_col = end_col,
              },
              url = abspath,
            }
          )
        end
      end
    end

    return images
  end,
})
