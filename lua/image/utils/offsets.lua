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
  local border = vim.api.nvim_win_get_config(window_id).border
  -- a list of 8 or any divisor of 8. if it's less than 8 long, it's repeated
  -- here we care about the top and the left, so positions 2 and 8
  if border ~= nil then
    if #border[(1 % #border) + 1] > 0 then y = y + 1 end
    if #border[(7 % #border) + 1] > 0 then x = x + 1 end
  end

  return { x = x, y = y }
end

return {
  get_global_offsets = get_global_offsets,
}
