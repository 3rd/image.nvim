local utils = require("image/utils")

local has_magick = vim.fn.executable("magick") == 1
local has_convert = vim.fn.executable("convert") == 1
local has_identify = vim.fn.executable("identify") == 1

-- magick v6 + v7
local convert_cmd = has_magick and "magick" or "convert"

local function guard()
  if not (has_magick or has_convert) then
    error("image.nvim: ImageMagick CLI tools not found (need 'magick' or 'convert')")
  end
  if not has_identify and not has_magick then error("image.nvim: ImageMagick 'identify' command not found") end
end

---@class MagickCliProcessor: ImageProcessor
local MagickCliProcessor = {}

function MagickCliProcessor.get_format(path)
  local result = utils.magic.detect_format(path)
  if result then return result end
  -- fallback to slower method:
  guard()
  local result = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  vim.loop.spawn(has_magick and "magick" or "identify", {
    args = has_magick and { "identify", "-format", "%m", path } or { "-format", "%m", path },
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

  local success = vim.wait(5000, function()
    return result ~= nil
  end, 10)
  if not success then error("identify format detection timed out") end
  return result
end

function MagickCliProcessor.convert_to_png(path, output_path)
  guard()

  local actual_format = MagickCliProcessor.get_format(path)

  local out_path = output_path or path:gsub("%.[^.]+$", ".png")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  -- for GIFs convert the first frame
  if actual_format == "gif" then path = path .. "[0]" end

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("convert timed out") end

  return out_path
end

function MagickCliProcessor.get_dimensions(path)
  local result = utils.dimensions.get_dimensions(path)
  if result then return result end
  -- fallback to slower method:
  guard()

  local actual_format = MagickCliProcessor.get_format(path)

  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  -- GIF
  if actual_format == "gif" then path = path .. "[0]" end

  vim.loop.spawn(has_magick and "magick" or "identify", {
    args = has_magick and { "identify", "-format", "%wx%h", path } or { "-format", "%wx%h", path },
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

  local success = vim.wait(5000, function()
    return result ~= nil
  end, 10)

  if not success then error("identify dimensions timed out") end

  return result
end

function MagickCliProcessor.resize(path, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-resized.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.crop(path, x, y, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-cropped.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("operation timed out") end

  return out_path
end

local build_transform_args = function(path, request, output_path)
  local source_path = path
  if (request.source_format or ""):lower() == "gif" then source_path = source_path .. "[0]" end

  local args = { source_path }
  if request.target_width and request.target_height then
    args[#args + 1] = "-scale"
    args[#args + 1] = string.format("%dx%d", request.target_width, request.target_height)
  end

  if request.crop then
    args[#args + 1] = "-crop"
    args[#args + 1] =
      string.format("%dx%d+%d+%d", request.crop.width, request.crop.height, request.crop.x, request.crop.y)
  end

  args[#args + 1] = (request.output_format or "png") .. ":" .. output_path
  return args
end

function MagickCliProcessor.transform(path, request, output_path, callback)
  guard()
  local stderr = vim.loop.new_pipe()
  local error_output = ""
  local handle = nil

  local close_stderr = function()
    if not stderr or stderr:is_closing() then return end
    pcall(vim.loop.read_stop, stderr)
    stderr:close()
  end

  handle = vim.loop.spawn(convert_cmd, {
    args = build_transform_args(path, request, output_path),
    stdio = { nil, nil, stderr },
    hide = true,
  }, function(code)
    close_stderr()
    if handle and not handle:is_closing() then handle:close() end
    if code == 0 then
      callback({ ok = true, path = output_path })
    else
      callback({ ok = false, error = error_output ~= "" and error_output or "Failed to transform image" })
    end
  end)

  if not handle then
    close_stderr()
    callback({ ok = false, error = "Failed to start image transform" })
    return
  end

  vim.loop.read_start(stderr, function(err, data)
    if err then
      error_output = error_output .. tostring(err)
      return
    end
    if data then error_output = error_output .. data end
    if data == nil then close_stderr() end
  end)
end

function MagickCliProcessor.brightness(path, brightness, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-bright.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.saturation(path, saturation, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-sat.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.hue(path, hue, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-hue.%1")
  local done = false
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
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

  local success = vim.wait(10000, function()
    return done
  end, 10)

  if not success then error("operation timed out") end

  return out_path
end

return MagickCliProcessor
