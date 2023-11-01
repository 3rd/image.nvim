---@param term_size { cell_width: number, cell_height: number }
---@param image_width number
---@param image_height number
---@param width number
---@param height number
local adjust_to_aspect_ratio = function(term_size, image_width, image_height, width, height)
  local aspect_ratio = image_width / image_height
  local pixel_width = width * term_size.cell_width
  local pixel_height = height * term_size.cell_height
  local percent_orig_width = pixel_width / image_width
  local percent_orig_height = pixel_height / image_height

  if width == 0 and height ~= 0 then
    width = math.max(1, math.floor(pixel_height / term_size.cell_width * aspect_ratio))
    return width, height
  end

  if height == 0 and width ~= 0 then
    height = math.max(1, math.floor(pixel_width / term_size.cell_height / aspect_ratio))
    return width, height
  end

  if percent_orig_height > percent_orig_width then
    local new_height = math.ceil(pixel_width / aspect_ratio / term_size.cell_height)
    return width, new_height
  else
    local new_width = math.ceil(pixel_height * aspect_ratio / term_size.cell_width)
    return new_width, height
  end
end

return {
  adjust_to_aspect_ratio = adjust_to_aspect_ratio,
}
