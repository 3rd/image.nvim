local dimensions = require("image/utils/dimensions")
local hash = require("image/utils/hash")
local json = require("image/utils/json")
local logger = require("image/utils/logger")
local magic = require("image/utils/magic")
local math = require("image/utils/math")
local offsets = require("image/utils/offsets")
local random = require("image/utils/random")
local term = require("image/utils/term")
local tmux = require("image/utils/tmux")
local virtual_padding = require("image/utils/virtual_padding")
local window = require("image/utils/window")

return {
  dimensions = dimensions,
  log = logger.log,
  throw = logger.throw,
  debug = logger.debug,
  random = random,
  window = window,
  term = term,
  math = math,
  offsets = offsets,
  tmux = tmux,
  magic = magic,
  hash = hash,
  json = json,
  virtual_padding = virtual_padding,
}
