local logger = require("image/utils/logger")
local random = require("image/utils/random")
local render = require("image/utils/render")
local window = require("image/utils/window")

local log = logger.create_logger({
  prefix = "[image.nvim]",
  formatter = logger.default_log_formatter,
  handler = print,
  output_file = "/tmp/nvim-image.txt",
})

local throw = logger.create_logger({
  prefix = "[image.nvim]",
  formatter = logger.default_log_formatter,
  handler = error,
  output_file = "/tmp/nvim-image.txt",
})

return {
  log = log,
  throw = throw,
  random = random,
  render = render,
  window = window,
}
