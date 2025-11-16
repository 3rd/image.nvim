local document = require("image/utils/document")

return document.create_document_integration({
  name = "rst",
  debug = true,
  default_options = {
    clear_in_insert_mode = true,
    download_remote_images = true,
    only_render_image_at_cursor = false,
    only_render_image_at_cursor_mode = "popup",
    floating_windows = false,
    filetypes = { "rst" },
  },
  query_buffer_images = function(buffer)
    local buf = buffer or vim.api.nvim_get_current_buf()
    local parser = vim.treesitter.get_parser(buf, "rst")
    parser:parse(true)

    local image_directive_query = vim.treesitter.query.parse("rst", [[
      ((directive
          name: (type) @_type
          body: (body (arguments) @url)) @image
       (#any-of? @_type "image" "figure"))
    ]])

    local images = {}

    local function get_images(tree)
      local root = tree:root()
      local current_image = nil

      for id, node in image_directive_query:iter_captures(root, buf) do
        local key = image_directive_query.captures[id]
        local value = vim.treesitter.get_node_text(node, buf)

        if key == "image" then
          local start_row, start_col, end_row, end_col = node:range()

          current_image = {
            node = node,
            range = {
              start_row = start_row,
              start_col = start_col,
              end_row = end_row,
              end_col = end_col,
            },
          }

        elseif current_image and key == "url" then
          current_image.url = value
          table.insert(images, current_image)
          current_image = nil
        end
      end
    end

    parser:for_each_tree(get_images)

    return images
  end
})
