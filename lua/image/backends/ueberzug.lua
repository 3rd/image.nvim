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

  vim.loop.read_start(stdout, function(err, _)
    assert(not err, err)
  end)

  vim.loop.read_start(stderr, function(err, _)
    assert(not err, err)
  end)

  local write = function(data)
    local serialized = vim.fn.json_encode(data)
    -- utils.debug("ueberzug:stdin", serialized)
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
  ---@diagnostic disable-next-line: assign-type-mismatch
  state = nil,
}
backend.setup = function(state)
  backend.state = state
  if not child then spawn() end
end
backend.render = function(image, x, y, width, height)
  if not child then return end
  child.write({
    action = "add",
    identifier = image.id,
    path = image.path,
    x = x,
    y = y,
    width = width,
    height = height,
  })
  backend.state.images[image.id] = image
end
backend.clear = function(image_id)
  if not child then return end
  if image_id then
    child.write({
      action = "remove",
      identifier = image_id,
    })
    backend.state.images[image_id] = nil
    return
  end
  for id, _ in pairs(backend.state.images) do
    child.write({
      action = "remove",
      identifier = id,
    })
    backend.state.images[id] = nil
  end
end

return backend
