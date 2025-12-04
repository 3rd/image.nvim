local document = require("image/utils/document")

local function create_fake_ts_node(text, start_row, start_col, end_row, end_col)
  local node = {}
  node._text = text
  node._range = { start_row, start_col, end_row, end_col }

  function node:range()
    return table.unpack(self._range)
  end

  function node:text()
    return self._text
  end

  return node
end

return document.create_document_integration({
  name = "asciidoc",
  debug = true,
  default_options = {
    clear_in_insert_mode = false,
    download_remote_images = true,
    only_render_image_at_cursor = false,
    only_render_image_at_cursor_mode = "popup",
    floating_windows = false,
    filetypes = { "asciidoc", "adoc" },
  },

  query_buffer_images = function(buffer)
    local buf = buffer or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local images = {}

    local pattern = "image::?([^%[]+)%[(.-)%]"

    for row, line in ipairs(lines) do
      for url, alt in line:gmatch(pattern) do
        local s, e = line:find("image:" .. url .. "[" .. alt .. "]", 1, true)
        if not s then
          s, e = line:find("image::" .. url .. "[" .. alt .. "]", 1, true)
        end
        if s and e then
          local node = create_fake_ts_node(line:sub(s, e), row - 1, s - 1, row - 1, e - 1)
          table.insert(images, {
            node = node,
            url = url,
            alt = alt,
            range = { start_row = row - 1, start_col = s - 1, end_row = row - 1, end_col = e - 1 },
          })
        end
      end
    end

    return images
  end,
})
