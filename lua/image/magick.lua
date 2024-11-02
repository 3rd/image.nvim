local has_magick, magick = pcall(require, "magick")

---@return MagickRockImage
local load_image = function(path)
  if not has_magick then
    local err = "image.nvim: magick not found"
    vim.api.nvim_err_writeln(err)
    error(err)
  end
  return magick.load_image(path)
end

return {
  has_magick = has_magick,
  magick = magick,
  load_image = load_image,
}
