# 🖼️ image.nvim

> **Warning**
>\
> This is very much a **work in progress**, **there are many bugs**, and there's lots to improve, but... we're getting there!

**image.nvim** is an attempt to add image support to Neovim.

https://github.com/3rd/image.nvim/assets/59587503/56a814d9-0bfa-436a-b0ca-fa8b9ef4d92b

## Requirements

These are things you have to setup on your own:
- [ImageMagick](https://github.com/ImageMagick/ImageMagick) - mandatory
- [magick LuaRock](https://github.com/leafo/magick) - mandatory (`luarocks --local install magick`)
- [Kitty](https://sw.kovidgoyal.net/kitty/) - for the `kitty` backend
- [ueberzugpp](https://github.com/jstkdng/ueberzugpp) - for the `ueberzug` backend
- [curl](https://github.com/curl/curl) - for remote images

On some distros, like NixOS, you will find that the `magick` LuaRock cannot find `libMagickWand.so`.

One way to fix it is to patch `~/.luarocks/share/lua/5.1/magick/wand/lib.lua` and change the first argument of the `try_to_load`
function to your `"/nix/store/xxxxxxxxxxxxxxxx-imagemagick-7.*.*-**/lib/libMagickWand-7.****.so"`.

After installing the `magick` LuaRock, you need to change your Neovim config to load it.

```lua
-- make sure that this happens before `image.nvim` is loaded:
package.path = package.path .. ";/home/you/.luarocks/share/lua/5.1/?/init.lua;"
package.path = package.path .. ";/home/you/.luarocks/share/lua/5.1/?.lua;"
```

## Configuration

```lua
-- default config
require("image").setup({
  backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
      sizing_strategy = "auto",
      download_remote_images = true,
      clear_in_insert_mode = false,
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  kitty_method = "normal",
  kitty_tmux_write_delay = 10, -- makes rendering more reliable with Kitty+Tmux
})
```

### Try it out with a minimal setup

Download [minimal-setup.lua](./minimal-setup.lua) from the root of this repository and run the demo with:

```sh
nvim --clean -c ":luafile minimal-setup.lua"
```


### Backends

- `kitty` (default and with Unicode placeholders, both work inside Tmux)
    - **Using Kitty with the default rendering mode is the best right now.**
    - Works great, is snappy and has very few artifacts (on my machine, at least).
- `ueberzug` - backed by [ueberzugpp](https://github.com/jstkdng/ueberzugpp)
    - It's more general but a bit slower.
    - Supports multiple images thanks to [@jstkdng](https://github.com/jstkdng/ueberzugpp/issues/74).
    - On-par with Kitty in terms of features, but slower.
- `sixels` - not implemented yet

### Integrations

Currently, there's a single integration for Markdown files, which is enabled by default.
\
Will add more soon and document them here.

- Markdown

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

- [@edluffy](https://github.com/edluffy) for [hologram.nvim](https://github.com/edluffy/hologram.nvim) - of which I borrowed a lot of code.
- [@kovidgoyal](https://github.com/kovidgoyal) for [Kitty](https://github.com/kovidgoyal/kitty) - the program I spend most of my time in.
- [@jstkdng](https://github.com/jstkdng) for [ueberzugpp](https://github.com/jstkdng/ueberzugpp) - the revived version of ueberzug.

### The story behind
Some years ago, I took a trip to Emacs land for a few months to learn Elisp and also research what Org-mode is, how it works,
and look for features of interest for my workflow.
I already had my own document syntax, albeit a very simple one, hacked together with Vimscript and a lot
of Regex, and I was looking for ideas to improve it and build features on top of it.

I kept working on my [syntax](https://github.com/3rd/syslang) over the years, rewrote it many times, and today it's a proper Tree-sitter grammar,
that I use for all my needs, from second braining to managing my tasks and time.
It's helped me control my ADHD and be productive long before I was diagnosed, and it's still helping me be so much better than I'd be without it today.

One thing Emacs and Org-mode had that I liked was the ability to embed images in the document. Of course, we don't *"need"* it, but... I really wanted to have images in my documents.

About 3 years ago, I made my [first attempt](https://github.com/3rd/vimage.nvim/tree/master) at solving this problem but didn't get far.
If you have similar interests, you might have seen the [vimage.nvim demo video](https://www.youtube.com/watch?v=cnt9mPOjrLg) on YouTube.

It was using [ueberzug](https://github.com/seebye/ueberzug), which is now dead. It was buggy and didn't handle things like window-relative positioning, attaching images to windows and buffers, folds, etc.

Kitty's graphics protocol was a thing, but it didn't work with Tmux, which I'll probably use forever or replace it with something of my own.

Now, things have changed, and I'm happy to announce that rendering images using [Kitty's graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol.html) from Neovim inside Tmux is working, and it's working pretty well!

My plan for this plugin is to support multiple backends, provide a few core integrations, and an easy-to-use API for other plugin authors to build on top of. There is a lot of logic that deals with positioning, cropping, bounds,
folds, extmarks, etc. that is painful and unrealistic to write from scratch for every plugin that wants to use images.

