local unload_processor = function()
  package.loaded["image/processors/magick_cli"] = nil
end

describe("magick cli processor transform", function()
  local originals

  before_each(function()
    originals = {
      executable = vim.fn.executable,
      new_pipe = vim.loop.new_pipe,
      read_start = vim.loop.read_start,
      read_stop = vim.loop.read_stop,
      spawn = vim.loop.spawn,
    }
  end)

  after_each(function()
    vim.fn.executable = originals.executable
    vim.loop.new_pipe = originals.new_pipe
    vim.loop.read_start = originals.read_start
    vim.loop.read_stop = originals.read_stop
    vim.loop.spawn = originals.spawn
    unload_processor()
  end)

  it("spawns one command for gif first-frame resize crop and png output", function()
    vim.fn.executable = function(command)
      return command == "magick" and 1 or 0
    end
    vim.loop.new_pipe = function()
      return {
        close = function() end,
        is_closing = function()
          return false
        end,
      }
    end
    vim.loop.read_start = function() end
    vim.loop.read_stop = function() end

    local spawned
    vim.loop.spawn = function(command, opts)
      spawned = {
        command = command,
        args = opts.args,
      }
      return {
        close = function() end,
        is_closing = function()
          return false
        end,
      }
    end

    local processor = require("image/processors/magick_cli")

    processor.transform("image.gif", {
      source_format = "gif",
      target_width = 20,
      target_height = 10,
      crop = {
        x = 1,
        y = 2,
        width = 7,
        height = 8,
      },
      output_format = "png",
    }, "out.png", function() end)

    assert.are.same("magick", spawned.command)
    assert.are.same({
      "image.gif[0]",
      "-scale",
      "20x10",
      "-crop",
      "7x8+1+2",
      "png:out.png",
    }, spawned.args)
  end)
end)
