local child = nil

local spawn = function()
  local stdin = vim.loop.new_pipe()
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()

  log("spawn")

  local handle, pid = vim.loop.spawn("ueberzug", {
    args = { "layer", "--silent" },
    stdio = { stdin, stdout, stderr },
  }, function(code, signal)
    child = nil
    print("code", code, "signal", signal)
  end)

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then log("stdout", data) end
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then log("stderr", data) end
  end)

  local write = function(data)
    local serialized = vim.fn.json_encode(data)
    -- log("write", serialized)
    vim.loop.write(stdin, serialized .. "\n")
  end

  local shutdown = function()
    vim.loop.shutdown(handle, function()
      -- log("shutdown")
      vim.loop.close(handle, function()
        -- log("close")
      end)
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

local clear = function(id)
  if not child then spawn() end
  if id then
    child.write({
      action = "remove",
      identifier = id,
    })
    return
  end
  child.write({
    action = "remove",
    identifier = "all",
  })
end

local render = function(id, url, x, y, width, height)
  if not child then spawn() end
  child.write({
    action = "add",
    identifier = id,
    path = url,
    x = x,
    y = y,
    max_width = width,
    max_height = height,
  })
end

return {
  clear = clear,
  render = render,
}
