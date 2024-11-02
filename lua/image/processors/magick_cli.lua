local utils = require("image/utils")

local has_convert = vim.fn.executable("convert") == 1
local has_identify = vim.fn.executable("identify") == 1

local function guard()
  if not has_convert or not has_identify then
    error("image.nvim: ImageMagick CLI tools (convert, identify) not found")
  end
end

---@class MagickCliProcessor: ImageProcessor
local MagickCliProcessor = {}

function MagickCliProcessor.get_format(path)
  guard()
  local result = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  vim.loop.spawn("identify", {
    args = { "-format", "%m", path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to get format") end
    result = output:lower():gsub("%s+$", "")
  end)

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then output = output .. data end
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not result do
    vim.loop.run("nowait")
  end

  return result
end

function MagickCliProcessor.convert_to_png(path, output_path)
  guard()
  local out_path = output_path or path:gsub("%.[^.]+$", ".png")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = { path, "png:" .. out_path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to convert to PNG") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

function MagickCliProcessor.get_dimensions(path)
  guard()
  local result = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  vim.loop.spawn("identify", {
    args = { "-format", "%wx%h", path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to get dimensions") end
    local width, height = output:match("(%d+)x(%d+)")
    result = { width = tonumber(width), height = tonumber(height) }
  end)

  vim.loop.read_start(stdout, function(err, data)
    assert(not err, err)
    if data then output = output .. data end
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not result do
    vim.loop.run("nowait")
  end

  return result
end

function MagickCliProcessor.resize(path, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-resized.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = {
      path,
      "-scale",
      string.format("%dx%d", width, height),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to resize") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

function MagickCliProcessor.crop(path, x, y, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-cropped.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = {
      path,
      "-crop",
      string.format("%dx%d+%d+%d", width, height, x, y),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to crop") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

function MagickCliProcessor.brightness(path, brightness, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-bright.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = {
      path,
      "-modulate",
      tostring(brightness),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to adjust brightness") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

function MagickCliProcessor.saturation(path, saturation, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-sat.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = {
      path,
      "-modulate",
      string.format("100,%d", saturation),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to adjust saturation") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

function MagickCliProcessor.hue(path, hue, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-hue.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn("convert", {
    args = {
      path,
      "-modulate",
      string.format("100,100,%d", hue),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then error(error_output ~= "" and error_output or "Failed to adjust hue") end
    done = true
  end)

  vim.loop.read_start(stderr, function(err, data)
    assert(not err, err)
    if data then error_output = error_output .. data end
  end)

  while not done do
    vim.loop.run("nowait")
  end

  return out_path
end

return MagickCliProcessor

