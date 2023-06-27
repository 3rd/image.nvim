local base64 = require("image/utils/base64")
local logger = require("image/utils/logger")
local png = require("image/utils/png")
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

local debug = logger.create_logger({
  prefix = "[image.nvim]",
  formatter = logger.default_log_formatter,
  handler = nil,
  output_file = "/tmp/nvim-image.txt",
})

return {
  log = log,
  throw = throw,
  debug = debug,
  base64 = base64,
  png = png,
  random = random,
  render = render,
  window = window,
}
