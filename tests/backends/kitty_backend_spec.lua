local codes = require("image/backends/kitty/codes")

local with_backend = function(callback)
  local originals = {
    backend = package.loaded["image/backends/kitty"],
    helpers = package.loaded["image/backends/kitty/helpers"],
    logger = package.loaded["image/utils/logger"],
    utils = package.loaded["image/utils"],
    create_autocmd = vim.api.nvim_create_autocmd,
  }
  local writes = {}

  vim.api.nvim_create_autocmd = function()
    return 1
  end
  package.loaded["image/backends/kitty"] = nil
  package.loaded["image/backends/kitty/helpers"] = {
    update_sync_start = function() end,
    update_sync_end = function() end,
    move_cursor = function() end,
    restore_cursor = function() end,
    write_placeholder = function() end,
    write_graphics = function(payload, data)
      writes[#writes + 1] = { payload = payload, data = data }
    end,
    write_graphics_at = function(payload)
      writes[#writes + 1] = { payload = payload }
    end,
  }
  package.loaded["image/utils/logger"] = {
    within = function()
      return {
        debug = function() end,
      }
    end,
  }
  package.loaded["image/utils"] = {
    term = {
      get_tty = function()
        return "/dev/pts/editor"
      end,
      get_size = function()
        return {
          cell_width = 1,
          cell_height = 1,
        }
      end,
    },
    tmux = {
      is_tmux = false,
      has_passthrough = true,
      get_pane_tty = function()
        return "/dev/pts/editor"
      end,
    },
  }

  local ok, err = pcall(function()
    local backend = require("image/backends/kitty")
    backend.setup({
      options = {
        kitty_method = "normal",
      },
      images = {},
    })
    callback(backend, writes)
  end)

  package.loaded["image/backends/kitty"] = originals.backend
  package.loaded["image/backends/kitty/helpers"] = originals.helpers
  package.loaded["image/utils/logger"] = originals.logger
  package.loaded["image/utils"] = originals.utils
  vim.api.nvim_create_autocmd = originals.create_autocmd

  if not ok then error(err) end
end

describe("kitty backend", function()
  it("retransmits after shallow clears delete terminal image data", function()
    with_backend(function(backend, writes)
      local image = {
        id = "image-id",
        internal_id = 10,
        cropped_path = "image.png",
        resize_hash = "10-10",
        crop_hash = nil,
        is_rendered = false,
        bounds = {
          top = 0,
          right = 100,
          bottom = 100,
          left = 0,
        },
      }

      backend.render(image, 0, 0, 10, 10)
      backend.clear(image.id, true)
      backend.render(image, 0, 0, 10, 10)

      local transmit_count = 0
      for _, write in ipairs(writes) do
        if write.payload.action == codes.control.action.transmit then transmit_count = transmit_count + 1 end
      end

      assert.are.same(2, transmit_count)
    end)
  end)
end)
