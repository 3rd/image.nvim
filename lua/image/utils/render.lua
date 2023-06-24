local get_window = require("image/utils/window").get_window

---@return number, number
local get_global_offsets = function()
  local x = 0
  if vim.opt.number then x = x + vim.opt.numberwidth:get() end
  if vim.opt.signcolumn ~= "no" then x = x + 2 end

  local y = 0
  if vim.opt.showtabline == 2 then y = y + 1 end
  if vim.opt.winbar ~= "none" then y = y + 1 end

  return x, y
end

---@param win Window|number
---@param x number
---@param y number
---@param max_width number
---@return { x: number, y: number, max_width: number, max_height: number, is_visible: boolean }
local relate_rect_to_window = function(win, x, y, max_width, max_height)
  local global_offset_x, global_offset_y = get_global_offsets()
  local window = type(win) == "number" and get_window(win) or win

  -- log("render", { window, x, y, max_width, max_height })

  local computed_x = window.x + x + global_offset_x - window.scroll_x
  local computed_y = window.y + y + global_offset_y - window.scroll_y + 1
  local computed_max_width = vim.fn.min({ max_width, window.width - computed_x })
  local computed_max_height = vim.fn.min({ max_height, window.height - computed_y })

  local is_visible = computed_y > 0 and computed_y < window.height and computed_x > 0 and computed_x < window.width

  return {
    x = computed_x,
    y = computed_y,
    max_width = computed_max_width,
    max_height = computed_max_height,
    is_visible = is_visible,
  }
end

return {
  get_global_offsets = get_global_offsets,
  relate_rect_to_window = relate_rect_to_window,
}
