local modrev, specrev = "scm", "-1"

local repo_url = "https://github.com/kevinm6/image.nvim"
local git_ref = "59d35492342f4afd74d74961cb9aafdb7caf29b9"

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
  dir = "image.nvim-" .. "59d35492342f4afd74d74961cb9aafdb7caf29b9",
}

if modrev == "scm" or modrev == "dev" then source = {
  url = repo_url:gsub("https", "git"),
} end

test_dependencies = {}

build = {
  type = "builtin",
  copy_directories = {},
}
