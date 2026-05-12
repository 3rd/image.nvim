local to_number = function(value, fallback)
  if type(value) == "number" then return value end
  return fallback
end

local get_positive_integer = function(value)
  if type(value) ~= "number" then return nil end
  if value <= 0 then return nil end
  if value ~= math.floor(value) then return nil end
  return value
end

---@param height number
---@param render_offset_top? number
---@param overlap? integer
---@return number
local get_reserved_lines = function(height, render_offset_top, overlap)
  local image_height = math.max(0, to_number(height, 0))
  local offset_top = to_number(render_offset_top, 0)
  local overlap_lines = get_positive_integer(overlap)

  -- nil or invalid overlap keeps normal virtual padding and still reserves render_offset_top rows.
  if overlap_lines == nil then return math.max(0, image_height + offset_top) end

  -- positive overlap counts real buffer lines covered by the image, including the anchor line.
  return math.max(0, image_height + offset_top - overlap_lines + 1)
end

---@param original_y number
---@param topline number
---@param winrow number
---@param height number
---@param render_offset_top? number
---@param overlap? integer
---@return number? absolute_y
---@return number? scrolled_lines
local get_overlap_scroll_position = function(original_y, topline, winrow, height, render_offset_top, overlap)
  local overlap_lines = get_positive_integer(overlap)
  if overlap_lines == nil then return nil end

  local anchor_line = original_y + 1
  local scrolled_lines = topline - anchor_line
  if scrolled_lines <= 0 then return nil end

  -- overlap only helps while the viewport is still inside the real lines covered by the image.
  if scrolled_lines >= overlap_lines then return nil end

  local offset_top = to_number(render_offset_top, 0)
  local visible_height = height + offset_top
  if scrolled_lines >= visible_height then return nil end

  return winrow + offset_top - scrolled_lines, scrolled_lines
end

return {
  get_reserved_lines = get_reserved_lines,
  get_overlap_scroll_position = get_overlap_scroll_position,
}
