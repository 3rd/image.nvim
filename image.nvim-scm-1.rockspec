local modrev, specrev = "scm", "-1"

local repo_url = "https://github.com/3rd/image.nvim"
local git_ref = "7d021c94e231d491355f5e724ba357ace296f06d"

rockspec_format = "3.0"
package = "image.nvim"
version = modrev .. specrev

description = {
  summary = "🖼️ Bringing images to Neovim.",
  detailed = "",
  labels = { "neovim", "neovim-plugin" },
  homepage = repo_url,
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "magick",
}

source = {
  url = repo_url .. "/archive/" .. git_ref .. ".zip",
  dir = "image.nvim-" .. git_ref,
}

if modrev == "scm" or modrev == "dev" then source = {
  url = repo_url:gsub("https", "git"),
} end

test_dependencies = {}

build = {
  type = "builtin",
  copy_directories = {},
}
