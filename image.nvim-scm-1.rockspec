local modrev, specrev = "scm", "-1"

rockspec_format = "3.0"
package = "image.nvim"
version = modrev .. specrev

description = {
  summary = "🖼️ Bringing images to Neovim.",
  detailed = "",
  labels = { "neovim", "neovim-plugin" },
  homepage = "https://github.com/3rd/image.nvim",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "magick",
}

source = {
  url = "git://github.com/3rd/image.nvim",
}

test_dependencies = {
  "nlua",
  "busted",
  "luassert",
}

test = {
  type = "busted",
  platforms = {
    unix = {
      flags = {
        "--config-file=.busted",
      },
    },
  },
}

build = {
  type = "builtin",
  copy_directories = {},
}
