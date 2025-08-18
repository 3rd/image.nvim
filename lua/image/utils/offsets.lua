---@param window_id number
---@return { top: number, right: number, bottom: number, left: number }
local get_border_shape = function(window_id)
  -- border
  local border = vim.api.nvim_win_get_config(window_id).border
  -- a list of 8 or any divisor of 8. if it's less than 8 long, it's repeated
  -- here we care about the top and the left, so positions 2 and 8
  local shape = { top = 0, right = 0, bottom = 0, left = 0 }
  if border ~= nil and type(border) == "table" then
    if #border[(1 % #border) + 1] > 0 then shape.top = 1 end
    if #border[(7 % #border) + 1] > 0 then shape.left = 1 end
    if #border[(5 % #border) + 1] > 0 then shape.bottom = 1 end
    if #border[(3 % #border) + 1] > 0 then shape.right = 1 end
  end
  return shape
end

---@param window_id number
---@return { x: number, y: number }
local get_global_offsets = function(window_id)
  local x = 0
  local y = 0
  -- if vim.opt.number then x = x + vim.opt.numberwidth:get() end
  -- if vim.opt.signcolumn ~= "no" then x = x + 2 end

  local opts = vim.wo[window_id]
  if not opts then return { x = x, y = y } end

  -- tabline
  if vim.opt.showtabline == 2 then y = y + 1 end

  -- winbar
  if opts.winbar ~= "" then y = y + 1 end

  -- gutters
  local wininfo = vim.fn.getwininfo(window_id)
  if wininfo and wininfo[1] then x = x + wininfo[1].textoff end

  -- border
  local border_dim = get_border_shape(window_id)
  x = x + border_dim.left
  y = y + border_dim.top

  return { x = x, y = y }
end

---Compute the width of virtual text
---@param vt table[] list of (text, highlight) tuples
---@return number
local virt_text_width = function(vt)
  local width = 0
  for _, tuple in ipairs(vt) do
    width = width + string.len(tuple[1])
  end
  return width
end

return {
  get_global_offsets = get_global_offsets,
  get_border_shape = get_border_shape,
  virt_text_width = virt_text_width,
}
