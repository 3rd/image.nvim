local document = require("image/utils/document")

return document.create_document_integration({
  name = "neorg",
  default_options = {
    clear_in_insert_mode = false,
    download_remote_images = true,
    only_render_image_at_cursor = false,
    filetypes = { "norg" },
  },
  query_buffer_images = function(buffer)
    local buf = buffer or vim.api.nvim_get_current_buf()

    local parser = vim.treesitter.get_parser(buf, "norg")
    local root = parser:parse()[1]:root()
    local query = vim.treesitter.query.parse("norg", '(infirm_tag (tag_name) @name (#eq? name "image"))')

    local images = {}

    ---@diagnostic disable-next-line: missing-parameter
    for id, node in query:iter_captures(root, 0) do
      local capture = query.captures[id]

      -- assume that everything after the tag + one space is the path/url and trim it
      if capture == "name" then
        local start_row, start_col, end_row, end_col = node:range()
        local line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1]
        local path = line:sub(end_col + 1):gsub("^%s*(.-)%s*$", "%1")

        table.insert(images, {
          node = node,
          range = { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col },
          url = path,
        })
      end
    end

    return images
  end,
})
