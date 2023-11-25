# 🖼️ image.nvim

This plugin attempts to add image support to Neovim.

It works wonderfully with Kitty + Tmux, and it handles painful things like rendering an image
at a given position in a buffer, scrolling, windows, etc.

It has built-in Markdown and Neorg integrations that you can use right now.
\
It can also render image files as images when opened.

Join on Discord: https://discord.gg/tQVKuZCZ

https://github.com/3rd/image.nvim/assets/59587503/9a9a1792-6476-4d96-8b8e-d3cdd7f5759e

## Requirements

These are things you have to setup on your own:

- [ImageMagick](https://github.com/ImageMagick/ImageMagick) - mandatory
- [magick LuaRock](https://github.com/leafo/magick) - mandatory (`luarocks --local install magick` or through your [package manager](https://github.com/vhyrro/hologram.nvim#install))
- [Kitty](https://sw.kovidgoyal.net/kitty/) >= 28.0 - for the `kitty` backend
- [ueberzugpp](https://github.com/jstkdng/ueberzugpp) - for the `ueberzug` backend
- [curl](https://github.com/curl/curl) - for remote images

After installing the `magick` LuaRock, you need to change your config to load it.

```lua
-- Example for configuring Neovim to load user-installed installed Lua rocks:
package.path = package.path .. ";" .. vim.fn.expand("$HOME") .. "/.luarocks/share/lua/5.1/?/init.lua;"
package.path = package.path .. ";" .. vim.fn.expand("$HOME") .. "/.luarocks/share/lua/5.1/?.lua;"
```

**NixOS** users need to install `imageMagick` and `luajitPackages.magick` ([thanks](https://github.com/NixOS/nixpkgs/pull/243687) to [@donovanglover](https://github.com/donovanglover)).
\
If you don't want to deal with setting up LuaRocks, you can build your Neovim with the rock installed:

<details>
<summary>With home-manager (thanks @wuliuqii https://github.com/3rd/image.nvim/issues/13)</summary>

```nix
{ pkgs, ... }:

{
  nixpkgs.overlays = [
    (import (builtins.fetchTarball {
      url =
        "https://github.com/nix-community/neovim-nightly-overlay/archive/master.tar.gz";
    }))
  ];
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-nightly;
    extraLuaPackages = ps: [ ps.magick ];
  };
}
```

</details>

<details>
<summary>Without home-manager</summary>

```nix
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/neovim/utils.nix#L27
{ pkgs, neovimUtils, wrapNeovimUnstable, ... }:

let
  config = pkgs.neovimUtils.makeNeovimConfig {
    extraLuaPackages = p: [ p.luarocks p.magick ];
    withNodeJs = false;
    withRuby = false;
    withPython3 = false;
    # https://github.com/NixOS/nixpkgs/issues/211998
    customRC = "luafile ~/.config/nvim/init.lua";
  };
in {
  nixpkgs.overlays = [
    (_: super: {
      neovim-custom = pkgs.wrapNeovimUnstable
        (super.neovim-unwrapped.overrideAttrs (oldAttrs: {
          version = "master";
          buildInputs = oldAttrs.buildInputs ++ [ super.tree-sitter ];
        })) config;
    })
  ];
  environment.systemPackages = with pkgs; [ neovim-custom ];
}
```

</details>

## Configuration

```lua
-- default config
require("image").setup({
  backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
      clear_in_insert_mode = false,
      download_remote_images = true,
      only_render_image_at_cursor = false,
      filetypes = { "markdown", "vimwiki" }, -- markdown extensions (ie. quarto) can go here
    },
    neorg = {
      enabled = true,
      clear_in_insert_mode = false,
      download_remote_images = true,
      only_render_image_at_cursor = false,
      filetypes = { "norg" },
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
  window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
  editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
  tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
  hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp" }, -- render image files as images when opened
})
```

## Tmux

- You must set: `set -gq allow-passthrough on`
- If you want the images to be automatically hidden/shown when you switch windows (`tmux_show_only_in_active_window = true`), set: `set -g visual-activity off`

### Try it out with a minimal setup

Download [minimal-setup.lua](./minimal-setup.lua) from the root of this repository and run the demo with:

```sh
nvim --clean -c ":luafile minimal-setup.lua"
```

### Backends

All the backends support rendering inside Tmux.

- `kitty` - best in class, works great and is very snappy
- `ueberzug` - backed by [ueberzugpp](https://github.com/jstkdng/ueberzugpp), supports any terminal, but has lower performance
  - Supports multiple images thanks to [@jstkdng](https://github.com/jstkdng/ueberzugpp/issues/74).

### Integrations

- `markdown` - uses [tree-sitter-markdown](https://github.com/MDeiml/tree-sitter-markdown) and supports any Markdown-based grammars (Quarto, VimWiki Markdown)
- `neorg` - uses [tree-sitter-norg](https://github.com/nvim-neorg/tree-sitter-norg) (also check https://github.com/nvim-neorg/neorg/issues/971)

## API

Check [types.lua](./lua/types.lua) for a better overview of how everything is modeled.

```lua
local api = require("image")

-- from a file (absolute path)
local image = api.from_file("/path/to/image.png", {
  id = "my_image_id", -- optional, defaults to a random string
  window = 1000, -- optional, binds image to a window and its bounds
  buffer = 1000, -- optional, binds image to a buffer (paired with window binding)
  with_virtual_padding = true, -- optional, pads vertically with extmarks
  ...geometry, -- optional, { x, y, width, height }
})

-- from a URL
local image = api.from_file("https://gist.ro/s/remote.png", {
  id = "my_image_id", -- optional, defaults to a random string
  window = 1000, -- optional, binds image to a window and its bounds
  buffer = 1000, -- optional, binds image to a buffer (paired with window binding)
  with_virtual_padding = true, -- optional, pads vertically with extmarks
  ...geometry, -- optional, { x, y, width, height }
})

image:render() -- render image
image:render(geometry) -- update image geometry and render it
image:clear()

image:move(x, y) -- move image
image:brightness(value) -- change brightness
image:saturation(value) -- change saturation
image:hue(value) -- change hue
```

---

### Thanks

- [@benlubas](https://github.com/benlubas) for their countless amazing contributions
- [@edluffy](https://github.com/edluffy) for [hologram.nvim](https://github.com/edluffy/hologram.nvim) - of which I borrowed a lot of code
- [@vhyrro](https://github.com/vhyrro) for their great ideas and [hologram.nvim fork](https://github.com/vhyrro/hologram.nvim) changes
- [@kovidgoyal](https://github.com/kovidgoyal) for [Kitty](https://github.com/kovidgoyal/kitty) - the program I spend most of my time in
- [@jstkdng](https://github.com/jstkdng) for [ueberzugpp](https://github.com/jstkdng/ueberzugpp) - the revived version of ueberzug

### The story behind

Some years ago, I took a trip to Emacs land for a few months to learn Elisp and also research what Org-mode is, how it works,
and look for features of interest for my workflow.
I already had my own document syntax, albeit a very simple one, hacked together with Vimscript and a lot
of Regex, and I was looking for ideas to improve it and build features on top of it.

I kept working on my [syntax](https://github.com/3rd/syslang) over the years, rewrote it many times, and today it's a proper Tree-sitter grammar,
that I use for all my needs, from second braining to managing my tasks and time.
It's helped me control my ADHD and be productive long before I was diagnosed, and it's still helping me be so much better than I'd be without it today.

One thing Emacs and Org-mode had that I liked was the ability to embed images in the document. Of course, we don't _"need"_ it, but... I really wanted to have images in my documents.

About 3 years ago, I made my [first attempt](https://www.reddit.com/r/neovim/comments/ieh7l4/im_building_an_image_plugin_and_need_some_help/) at solving this problem but didn't get far.
If you have similar interests, you might have seen the [vimage.nvim demo video](https://www.youtube.com/watch?v=cnt9mPOjrLg) on YouTube.

It was using [ueberzug](https://github.com/seebye/ueberzug), which is now dead. It was buggy and didn't handle things like window-relative positioning, attaching images to windows and buffers, folds, etc.

Kitty's graphics protocol was a thing, but it didn't work with Tmux, which I'll probably use forever or replace it with something of my own.

Now, things have changed, and I'm happy to announce that rendering images using [Kitty's graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol.html) from Neovim inside Tmux is working, and it's working pretty well!

My plan for this plugin is to support multiple backends, provide a few core integrations, and an easy-to-use API for other plugin authors to build on top of. There is a lot of logic that deals with positioning, cropping, bounds,
folds, extmarks, etc. that is painful and unrealistic to write from scratch for every plugin that wants to use images.
