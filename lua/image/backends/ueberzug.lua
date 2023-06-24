local utils = require("image/utils")

local child = nil
local should_be_alive = false

local spawn = function()
  local stdin = vim.loop.new_pipe()
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  should_be_alive = true

  local handle, pid = vim.loop.spawn("ueberzug", {
    args = { "layer", "--silent" },
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    child = nil
    if should_be_alive then
      utils.throw("image: ueberzug died unexpectedly", {
        code = code,
        signal = signal,
      })
    end
  end)

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then utils.log("ueberzug:stdout", data) end
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then utils.log("ueberzug:stderr", data) end
  end)

  local write = function(data)
    local serialized = vim.fn.json_encode(data)
    vim.loop.write(stdin, serialized .. "\n")
  end

  local shutdown = function()
    should_be_alive = false
    vim.loop.shutdown(handle, function()
      vim.loop.close(handle, function() end)
    end)
  end

  child = {
    handle = handle,
    pid = pid,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    write = write,
    shutdown = shutdown,
  }
end

---@type Backend
local backend = {
  setup = function()
    if not child then spawn() end
  end,
  render = function(image_id, url, x, y, max_cols, max_rows)
    child.write({
      action = "add",
      identifier = image_id,
      path = url,
      x = x,
      y = y,
      max_cols = max_cols,
      max_rows = max_rows,
    })
  end,
  clear = function(image_id)
    if image_id then
      child.write({
        action = "remove",
        identifier = image_id,
      })
      return
    end
    child.write({
      action = "remove",
      identifier = "all",
    })
  end,
}

return backend
