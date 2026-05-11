local has_magick, magick = pcall(require, "magick")

local missing_magick_rock_error = nil
if not has_magick then
  missing_magick_rock_error = "image.nvim: magick rock not found, please install it and restart your editor. Error: "
    .. vim.inspect(magick)
end

local function warn_if_magick_rock_missing()
  if not missing_magick_rock_error then return end
  vim.api.nvim_err_writeln(missing_magick_rock_error)
end

---@return MagickRockImage
local load_image = function(path)
  if missing_magick_rock_error then
    vim.api.nvim_err_writeln(missing_magick_rock_error)
    error(missing_magick_rock_error)
  end
  return magick.load_image(path)
end

return {
  has_magick = has_magick,
  magick = magick,
  load_image = load_image,
  warn_if_magick_rock_missing = warn_if_magick_rock_missing,
}
