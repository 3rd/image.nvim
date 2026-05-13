local offsets = require("image/utils/offsets")

---@param id number
---@param opts { with_scroll?: boolean }
---@return number
local get_scroll_y = function(id, opts)
  if not opts.with_scroll then return 0 end

  local ok, topline = pcall(vim.fn.win_execute, id, "echo line('w0')")
  if not ok then return 0 end

  return (tonumber(topline) or 1) - 1
end

local is_treesitter_context_window = function(window, target_window)
  if not window.is_floating then return false end

  local config = vim.api.nvim_win_get_config(window.id)
  if config.relative ~= "win" then return false end
  if config.win ~= target_window.id then return false end
  if config.row ~= 0 then return false end
  if config.focusable ~= false then return false end
  if config.mouse ~= false then return false end
  if (config.zindex or 0) ~= 20 then return false end
  if window.buffer_filetype ~= "" then return false end
  if vim.bo[window.buffer].buftype ~= "nofile" then return false end
  if vim.api.nvim_buf_get_name(window.buffer) ~= "" then return false end

  return true
end

---@param opts? { normal?: boolean, floating?: boolean, with_masks?: boolean, with_scroll?: boolean, ignore_masking_filetypes?: string[] }
---@return Window[]
local get_windows = function(opts)
  opts = opts or {}
  local windows = {} ---@type Window[]
  for _, id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buffer = vim.api.nvim_win_get_buf(id)
    local columns = vim.api.nvim_win_get_width(id)
    local rows = vim.api.nvim_win_get_height(id)
    local pos = vim.api.nvim_win_get_position(id)
    local config = vim.api.nvim_win_get_config(id)
    local buffer_filetype = vim.bo[buffer].filetype
    local bufinfo = vim.fn.getbufinfo(buffer)[1]
    local buffer_is_listed = bufinfo and bufinfo.listed == 1
    local scroll_x = 0 -- TODO:
    local scroll_y = get_scroll_y(id, opts)
    local is_visible = true

    local rect_top, rect_left
    local content_width = columns
    local content_height = rows

    if config.relative ~= "" then
      -- floating
      local screen_pos = vim.fn.screenpos(id, 1, 1)
      rect_top = screen_pos.row - 2
      rect_left = screen_pos.col - 1
    else
      -- normal
      rect_top = pos[1]
      rect_left = pos[2]
    end

    local window = {
      id = id,
      buffer = buffer,
      buffer_filetype = buffer_filetype,
      buffer_is_listed = buffer_is_listed,
      x = pos[2],
      y = pos[1],
      scroll_x = scroll_x,
      scroll_y = scroll_y,
      width = columns,
      height = rows,
      is_visible = is_visible,
      is_normal = config.relative == "",
      is_floating = config.relative ~= "",
      zindex = config.zindex or 0,
      rect = {
        top = rect_top,
        right = rect_left + content_width,
        bottom = rect_top + content_height - (config.relative == "" and vim.o.laststatus == 2 and 1 or 0),
        left = rect_left,
      },
      masks = {},
    }
    table.insert(windows, window)
  end

  -- compute masks for normal windows
  if opts.with_masks then
    local ignore_masking_filetypes = opts.ignore_masking_filetypes or {}

    for _, window in ipairs(windows) do
      local masks = {}
      if not window.is_normal then goto continue end

      for _, other_window in ipairs(windows) do
        if window.id == other_window.id then goto continue_inner end
        if not other_window.is_floating then goto continue_inner end
        if vim.w[other_window.id].treesitter_context then goto continue_inner end
        if is_treesitter_context_window(other_window, window) then goto continue_inner end
        if vim.tbl_contains(ignore_masking_filetypes, other_window.buffer_filetype) then goto continue_inner end

        local is_overlapping = (
          other_window.zindex > window.zindex
          and other_window.rect.left < window.rect.right
          and other_window.rect.right > window.rect.left
          and other_window.rect.top < window.rect.bottom
          and other_window.rect.bottom > window.rect.top
        )
        if is_overlapping then
          table.insert(masks, {
            x = other_window.rect.left - window.rect.left,
            y = other_window.rect.top - window.rect.top,
            width = other_window.width - (other_window.rect.left - window.rect.left),
            height = other_window.height - (other_window.rect.top - window.rect.top),
          })
        end
        ::continue_inner::
      end

      for _, mask in ipairs(masks) do
        -- flag fully-masked windows
        if mask.x == 0 and mask.y == 0 and mask.width == window.width and mask.height == window.height then
          window.is_visible = false
          goto continue
        end
        -- TODO: merge masks, recompute is_visible
      end

      ::continue::
      window.masks = masks
    end
  end

  local result = {}
  for _, window in ipairs(windows) do
    if opts.normal and window.is_normal then table.insert(result, window) end
    if opts.floating and window.is_floating then table.insert(result, window) end
  end
  return result
end

---@param opts? { with_masks?: boolean, with_scroll?: boolean, ignore_masking_filetypes?: string[] }
---@return Window|nil
local get_window = function(id, opts)
  if not vim.api.nvim_win_is_valid(id) then return nil end
  local windows = get_windows(vim.tbl_extend("force", opts or {}, { normal = true, floating = true }))
  for _, window in ipairs(windows) do
    if window.id == id then return window end
  end
  return nil
end

return {
  get_window = get_window,
  get_windows = get_windows,
}
