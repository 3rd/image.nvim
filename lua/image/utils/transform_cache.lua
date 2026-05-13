local hash = require("image/utils/hash")

local uv = vim.uv or vim.loop
local entries = {}
local path_entries = {}
local path_sources = {}
local access_counter = 0

-- transformed variants live in tmp_dir and are reused until the canonical source stat changes.
local mtime_key = function(stat)
  if not stat or not stat.mtime then return "0:0" end
  return ("%s:%s"):format(stat.mtime.sec or 0, stat.mtime.nsec or 0)
end

local canonical_path = function(path)
  if not path then return nil end
  local absolute_path = vim.fn.fnamemodify(path, ":p")
  return uv.fs_realpath(absolute_path) or absolute_path
end

local source_identity = function(path)
  local canonical = canonical_path(path)
  if not canonical then return nil, "missing source path" end

  local stat = uv.fs_stat(canonical)
  if not stat then return nil, ("source not found: %s"):format(canonical) end

  return {
    path = canonical,
    mtime = mtime_key(stat),
    size = stat.size or 0,
  }
end

local crop_key = function(crop)
  if not crop then return "none" end
  return ("%d:%d:%d:%d"):format(crop.x, crop.y, crop.width, crop.height)
end

local build_key = function(request)
  return hash.sha256(table.concat({
    request.source.path,
    request.source.mtime,
    tostring(request.source.size),
    request.source_format or "",
    tostring(request.target_width or 0),
    tostring(request.target_height or 0),
    crop_key(request.crop),
    request.processor or "",
    tostring(request.backend_crop or false),
    request.output_format or "png",
  }, "|"))
end

local remove_entry = function(key)
  local entry = entries[key]
  if not entry then return end

  entries[key] = nil
  local source_entries = path_entries[entry.source.path]
  if not source_entries then return end

  source_entries[key] = nil
  if next(source_entries) == nil then
    path_entries[entry.source.path] = nil
    path_sources[entry.source.path] = nil
  end
end

local index_entry = function(entry)
  path_entries[entry.source.path] = path_entries[entry.source.path] or {}
  path_entries[entry.source.path][entry.key] = true
  path_sources[entry.source.path] = {
    mtime = entry.source.mtime,
    size = entry.source.size,
  }
end

local remove_source_entries = function(path)
  local source_entries = path_entries[path]
  if not source_entries then return end

  local keys = {}
  for key in pairs(source_entries) do
    keys[#keys + 1] = key
  end

  for _, key in ipairs(keys) do
    remove_entry(key)
  end
end

local invalidate_changed_source = function(source)
  local previous = path_sources[source.path]
  if previous and (previous.mtime ~= source.mtime or previous.size ~= source.size) then remove_source_entries(source.path) end
  path_sources[source.path] = {
    mtime = source.mtime,
    size = source.size,
  }
end

local output_path_for_key = function(tmp_dir, key, output_format)
  return ("%s/transform-%s.%s"):format(tmp_dir, key, output_format or "png")
end

local schedule_callbacks = function(callbacks, entry)
  if #callbacks == 0 then return end
  vim.schedule(function()
    for _, callback in ipairs(callbacks) do
      callback(entry)
    end
  end)
end

local complete_entry = function(entry, result)
  if entries[entry.key] ~= entry then return end

  access_counter = access_counter + 1
  entry.last_access = access_counter

  if result and result.ok then
    entry.status = "complete"
    entry.output_path = result.path or entry.output_path
    entry.error = nil
  else
    entry.status = "failed"
    entry.error = result and result.error or "transform failed"
  end

  local callbacks = entry.callbacks or {}
  entry.callbacks = nil
  schedule_callbacks(callbacks, entry)
end

local get_or_queue = function(request, tmp_dir, start_transform, on_complete)
  request.key = request.key or build_key(request)
  invalidate_changed_source(request.source)

  local entry = entries[request.key]
  if entry and entry.status == "complete" and vim.fn.filereadable(entry.output_path) ~= 1 then
    remove_entry(request.key)
    entry = nil
  end

  access_counter = access_counter + 1

  if entry then
    entry.last_access = access_counter
    if entry.status == "pending" and on_complete then entry.callbacks[#entry.callbacks + 1] = on_complete end
    return entry
  end

  entry = {
    key = request.key,
    status = "pending",
    source = request.source,
    output_path = output_path_for_key(tmp_dir, request.key, request.output_format),
    callbacks = on_complete and { on_complete } or {},
    last_access = access_counter,
  }

  entries[request.key] = entry
  index_entry(entry)

  local ok, err = pcall(start_transform, entry.output_path, function(result)
    complete_entry(entry, result)
  end)
  if not ok then complete_entry(entry, { ok = false, error = err }) end

  return entry
end

local clear_for_path = function(path)
  local canonical = canonical_path(path)
  if not canonical then return end
  remove_source_entries(canonical)
end

local clear = function()
  entries = {}
  path_entries = {}
  path_sources = {}
  access_counter = 0
end

return {
  build_key = build_key,
  clear = clear,
  clear_for_path = clear_for_path,
  get_or_queue = get_or_queue,
  source_identity = source_identity,
}
