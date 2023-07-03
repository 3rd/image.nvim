local has_magick, magick = pcall(require, "magick")

---@return MagickImage
local load_image = function(path)
  if not has_magick then error("image.nvim: magick not found") end
  return magick.load_image(path)
end

return {
  has_magick = has_magick,
  magick = magick,
  load_image = load_image,
}
