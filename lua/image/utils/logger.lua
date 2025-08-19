local M = {}

-- log levels
local levels = {
  debug = 10,
  info = 20,
  warn = 30,
  error = 40,
}

-- default configuration
local config = {
  enabled = false,
  level = "detailed",
  file_path = nil,
  format = "compact",
}

-- formatters
local formatters = {}

formatters.image = function(img)
  if not img then return "nil" end
  if type(img) ~= "table" then return tostring(img) end

  local parts = { "Image[" }
  if img.id then table.insert(parts, "id=" .. tostring(img.id)) end
  if img.geometry then
    table.insert(parts, string.format("%dx%d", img.geometry.width or 0, img.geometry.height or 0))
    table.insert(parts, string.format("@ (%d,%d)", img.geometry.x or 0, img.geometry.y or 0))
  elseif img.width and img.height then
    table.insert(parts, string.format("%dx%d", img.width, img.height))
    if img.x and img.y then table.insert(parts, string.format("@ (%d,%d)", img.x, img.y)) end
  end
  if img.path then
    local filename = vim.fn.fnamemodify(img.path, ":t")
    table.insert(parts, "file=" .. filename)
  end
  table.insert(parts, "]")
  return table.concat(parts, " ")
end

formatters.geometry = function(geom)
  if not geom then return "nil" end
  if type(geom) ~= "table" then return tostring(geom) end
  return string.format("Geom[%dx%d+%d+%d]", geom.width or 0, geom.height or 0, geom.x or 0, geom.y or 0)
end

formatters.window = function(win)
  if not win then return "nil" end
  if type(win) == "number" then return string.format("Win[#%d]", win) end
  if type(win) ~= "table" then return tostring(win) end

  local parts = { "Win[" }
  if win.id then table.insert(parts, "#" .. tostring(win.id)) end
  if win.buffer then table.insert(parts, "buf:" .. tostring(win.buffer)) end
  if win.width and win.height then table.insert(parts, string.format("%dx%d", win.width, win.height)) end
  table.insert(parts, "]")
  return table.concat(parts, " ")
end

formatters.bounds = function(bounds)
  if not bounds then return "nil" end
  if type(bounds) ~= "table" then return tostring(bounds) end
  return string.format(
    "Bounds[t:%d,b:%d,l:%d,r:%d]",
    bounds.top or 0,
    bounds.bottom or 0,
    bounds.left or 0,
    bounds.right or 0
  )
end

formatters.table = function(t, max_depth)
  if not t then return "nil" end
  if type(t) ~= "table" then return tostring(t) end

  max_depth = max_depth or 2
  local seen = {}

  local function format_value(v, depth)
    if depth > max_depth then return "..." end

    local vtype = type(v)
    if vtype == "nil" then
      return "nil"
    elseif vtype == "boolean" or vtype == "number" then
      return tostring(v)
    elseif vtype == "string" then
      if #v > 80 then return string.format('"%s..."', v:sub(1, 77)) end
      return string.format('"%s"', v)
    elseif vtype == "function" then
      return "<function>"
    elseif vtype == "table" then
      if seen[v] then return "<circular>" end
      seen[v] = true

      -- brittle handling for special types
      if v.id and v.geometry then
        return formatters.image(v)
      elseif v.width and v.height and v.x and v.y then
        return formatters.geometry(v)
      elseif v.top and v.bottom and v.left and v.right then
        return formatters.bounds(v)
      end

      local count = 0
      for _ in pairs(v) do
        count = count + 1
        if count > 3 then break end
      end

      if count <= 3 and depth < max_depth then
        local items = {}
        for k, val in pairs(v) do
          table.insert(items, string.format("%s=%s", tostring(k), format_value(val, depth + 1)))
        end
        return "{" .. table.concat(items, ", ") .. "}"
      else
        return string.format("<table:%d items>", count)
      end
    else
      return "<" .. vtype .. ">"
    end
  end

  return format_value(t, 1)
end

local function format_data(data)
  if data == nil then return "" end

  local dtype = type(data)
  if dtype == "string" or dtype == "number" or dtype == "boolean" then
    return tostring(data)
  elseif dtype == "table" then
    if data.id and (data.geometry or data.path) then
      return formatters.image(data)
    elseif data.width and data.height and data.x and data.y then
      return formatters.geometry(data)
    elseif data.top and data.bottom and data.left and data.right then
      return formatters.bounds(data)
    else
      return formatters.table(data)
    end
  else
    return tostring(data)
  end
end

local base_hrtime = vim.loop.hrtime()
local function get_timestamp()
  if config.format == "detailed" then
    local elapsed_ns = vim.loop.hrtime() - base_hrtime
    local elapsed_s = elapsed_ns / 1e9
    local time_s = os.time() + math.floor(elapsed_s)
    local frac_s = elapsed_s % 1
    return string.format("%s.%03d", os.date("%H:%M:%S", time_s), math.floor(frac_s * 1e3))
  else
    local elapsed_ms = (vim.loop.hrtime() - base_hrtime) / 1e6
    return string.format("%06d", math.floor(elapsed_ms))
  end
end

local function should_log(level)
  if not config.enabled or not config.file_path then return false end

  -- check level
  local min_level = levels[config.level] or levels.debug
  local msg_level = levels[level] or levels.debug
  if msg_level < min_level then return false end

  return true
end

local function output_log(formatted_msg)
  if config.file_path then
    local file = io.open(config.file_path, "a")
    if file then
      file:write(formatted_msg .. "\n")
      file:close()
    end
  end
end

local function log_message(level, category, message, data)
  if not should_log(level) then return end

  if type(message) == "function" then
    local ok, result = pcall(message)
    if not ok then return end
    message = result
  end

  if type(data) == "function" then
    local ok, result = pcall(data)
    if not ok then
      data = nil
    else
      data = result
    end
  end

  local parts = {}

  if config.format == "detailed" then
    table.insert(parts, get_timestamp())
    table.insert(parts, string.format("[%s]", level:upper()))
    if category and category ~= "" then table.insert(parts, string.format("[%s]", category)) end
  else
    table.insert(parts, get_timestamp())
    if category and category ~= "" then
      table.insert(parts, string.format("%s/%s:", category, level:sub(1, 1)))
    else
      table.insert(parts, string.format("%s:", level:sub(1, 1)))
    end
  end

  table.insert(parts, message)

  if data then
    local formatted = format_data(data)
    if formatted and formatted ~= "" then table.insert(parts, formatted) end
  end

  local formatted_msg = table.concat(parts, " ")
  output_log(formatted_msg)
end

function M.setup(opts)
  if opts then config = vim.tbl_deep_extend("force", config, opts) end
end

function M.within(category)
  local bound_logger = {}

  function bound_logger.debug(message, data)
    log_message("debug", category, message, data)
  end

  function bound_logger.info(message, data)
    log_message("info", category, message, data)
  end

  function bound_logger.warn(message, data)
    log_message("warn", category, message, data)
  end

  function bound_logger.error(message, data)
    log_message("error", category, message, data)
  end

  setmetatable(bound_logger, {
    __call = function(_, message, data)
      log_message("debug", category, message, data)
    end,
  })

  return bound_logger
end

function M.debug(category, message, data)
  log_message("debug", category, message, data)
end

function M.info(category, message, data)
  log_message("info", category, message, data)
end

function M.warn(category, message, data)
  log_message("warn", category, message, data)
end

function M.error(category, message, data)
  log_message("error", category, message, data)
end

M.throw = function(msg, data)
  log_message("error", "", msg, data)
  error(msg)
end

setmetatable(M, {
  __call = function(_, category, message, data)
    log_message("debug", category, message, data)
  end,
})

return M

