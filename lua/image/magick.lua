local has_magick, magick = pcall(require, "magick")

---@return MagickImage
local load_image = function(path)
  if not has_magick then
    local err = "image.nvim: magick not found"
    vim.api.nvim_err_writeln(err)
    error(err)
  end
  return magick.load_image(path)
end

---@return MagickImage
local load_image_from_blob = function(data)
  if not has_magick then
    local err = "image.nvim: magick not found"
    vim.api.nvim_err_writeln(err)
    error(err)
  end
  return magick.load_image_from_blob(data)
end

return {
  has_magick = has_magick,
  magick = magick,
  load_image = load_image,
  load_image_from_blob = load_image_from_blob,
}
