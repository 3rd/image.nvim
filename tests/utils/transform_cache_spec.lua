local unload_cache = function()
  package.loaded["image/utils/transform_cache"] = nil
end

describe("transform cache", function()
  local cache
  local original_schedule
  local output_paths
  local scheduled
  local temp_path

  local make_request = function()
    local source = assert(cache.source_identity(temp_path))
    return {
      source = source,
      source_format = "png",
      target_width = 10,
      target_height = 10,
      crop = nil,
      processor = "magick_cli",
      backend_crop = true,
      output_format = "png",
    }
  end

  before_each(function()
    unload_cache()
    cache = require("image/utils/transform_cache")
    temp_path = vim.fn.tempname()
    vim.fn.writefile({ "first" }, temp_path)
    output_paths = {}
    scheduled = {}
    original_schedule = vim.schedule
    vim.schedule = function(callback)
      scheduled[#scheduled + 1] = callback
    end
  end)

  after_each(function()
    cache.clear()
    vim.schedule = original_schedule
    vim.fn.delete(temp_path)
    for _, path in ipairs(output_paths) do
      vim.fn.delete(path)
    end
    unload_cache()
  end)

  it("deduplicates pending work and reuses completed entries", function()
    local starts = 0
    local complete
    local callbacks = 0

    local first = cache.get_or_queue(make_request(), "/tmp", function(_, on_complete)
      starts = starts + 1
      complete = on_complete
    end, function()
      callbacks = callbacks + 1
    end)
    local second = cache.get_or_queue(make_request(), "/tmp", function()
      starts = starts + 1
    end, function()
      callbacks = callbacks + 1
    end)

    assert.are.equal(first, second)
    assert.are.same("pending", first.status)
    assert.are.same(1, starts)

    output_paths[#output_paths + 1] = first.output_path
    vim.fn.writefile({ "output" }, first.output_path)
    complete({ ok = true, path = first.output_path })
    assert.are.same(1, #scheduled)
    scheduled[1]()

    assert.are.same(2, callbacks)

    local completed = cache.get_or_queue(make_request(), "/tmp", function()
      starts = starts + 1
    end)

    assert.are.equal(first, completed)
    assert.are.same("complete", completed.status)
    assert.are.same(1, starts)
  end)

  it("suppresses failed entries until source stat changes", function()
    local starts = 0
    local complete

    local failed = cache.get_or_queue(make_request(), "/tmp", function(_, on_complete)
      starts = starts + 1
      complete = on_complete
    end)
    complete({ ok = false, error = "boom" })

    assert.are.same("failed", failed.status)

    local same_source = cache.get_or_queue(make_request(), "/tmp", function()
      starts = starts + 1
    end)

    assert.are.equal(failed, same_source)
    assert.are.same(1, starts)

    vim.fn.writefile({ "changed", "content" }, temp_path)

    local changed_source = cache.get_or_queue(make_request(), "/tmp", function()
      starts = starts + 1
    end)

    assert.are.same("pending", changed_source.status)
    assert.are.same(2, starts)
  end)

  it("uses canonical source paths for equivalent file names", function()
    local direct = assert(cache.source_identity(temp_path))
    local equivalent =
      assert(cache.source_identity(vim.fn.fnamemodify(temp_path, ":h") .. "/./" .. vim.fn.fnamemodify(temp_path, ":t")))

    assert.are.same(direct.path, equivalent.path)
  end)
end)
