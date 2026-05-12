local codes = require("image/backends/kitty/codes")

local with_helpers = function(opts, callback)
  local originals = {
    io_open = io.open,
    new_tty = vim.loop.new_tty,
    loop_sleep = vim.loop.sleep,
    uv_sleep = vim.uv and vim.uv.sleep or nil,
    helpers = package.loaded["image/backends/kitty/helpers"],
    logger = package.loaded["image/utils/logger"],
    utils = package.loaded["image/utils"],
  }
  local stdout_writes = {}

  io.open = opts.open or io.open
  vim.loop.new_tty = function()
    return {
      write = function(_, payload)
        table.insert(stdout_writes, payload)
      end,
    }
  end
  vim.loop.sleep = function() end
  if vim.uv then vim.uv.sleep = function() end end

  package.loaded["image/backends/kitty/helpers"] = nil
  package.loaded["image/utils/logger"] = {
    within = function()
      return {
        debug = function() end,
      }
    end,
  }
  package.loaded["image/utils"] = {
    tmux = {
      is_tmux = false,
      escape = function(payload)
        return payload
      end,
    },
  }

  local ok, err = pcall(function()
    callback(require("image/backends/kitty/helpers"), stdout_writes)
  end)

  io.open = originals.io_open
  vim.loop.new_tty = originals.new_tty
  vim.loop.sleep = originals.loop_sleep
  if vim.uv then vim.uv.sleep = originals.uv_sleep end
  package.loaded["image/backends/kitty/helpers"] = originals.helpers
  package.loaded["image/utils/logger"] = originals.logger
  package.loaded["image/utils"] = originals.utils

  if not ok then error(err) end
end

describe("kitty helpers", function()
  it("closes direct-transmit files after reading", function()
    local handle = {
      closed = false,
      read = function(_, mode)
        assert.is_equal("*all", mode)
        return "abc"
      end,
      close = function(self)
        self.closed = true
      end,
    }

    with_helpers({
      open = function(path, mode)
        assert.is_equal("image.png", path)
        assert.is_equal("rb", mode)
        return handle
      end,
    }, function(helpers, stdout_writes)
      helpers.write_graphics({
        transmit_medium = codes.control.transmit_medium.direct,
      }, "image.png")

      assert.is_true(handle.closed)
      assert.is_not_nil(stdout_writes[1]:find("YWJj", 1, true))
    end)
  end)

  it("closes direct-transmit files when reading fails", function()
    local handle = {
      closed = false,
      read = function()
        error("read failed")
      end,
      close = function(self)
        self.closed = true
      end,
    }

    with_helpers({
      open = function()
        return handle
      end,
    }, function(helpers)
      local ok, err = pcall(function()
        helpers.write_graphics({
          transmit_medium = codes.control.transmit_medium.direct,
        }, "image.png")
      end)

      assert.is_false(ok)
      assert.is_true(handle.closed)
      assert.is_not_nil(tostring(err):find("read failed", 1, true))
    end)
  end)

  it("closes tty override handles after writing", function()
    local handle = {
      closed = false,
      written = nil,
      write = function(self, payload)
        self.written = payload
      end,
      close = function(self)
        self.closed = true
      end,
    }

    with_helpers({
      open = function(path, mode)
        assert.is_equal("/dev/pts/test", path)
        assert.is_equal("w", mode)
        return handle
      end,
    }, function(helpers)
      helpers.write("payload", "/dev/pts/test")

      assert.is_equal("payload", handle.written)
      assert.is_true(handle.closed)
    end)
  end)

  it("closes tty override handles when writing fails", function()
    local handle = {
      closed = false,
      write = function()
        error("write failed")
      end,
      close = function(self)
        self.closed = true
      end,
    }

    with_helpers({
      open = function()
        return handle
      end,
    }, function(helpers)
      local ok, err = pcall(function()
        helpers.write("payload", "/dev/pts/test")
      end)

      assert.is_false(ok)
      assert.is_true(handle.closed)
      assert.is_not_nil(tostring(err):find("write failed", 1, true))
    end)
  end)
end)
