# image.nvim

> **Warning**
> This is very much a **work in progress**, **there are many bugs**, and there's lots to improve, but... we're getting there!

🖼️ **image.nvim** is an attempt to add image support to Neovim.

## Configuration

> **Warning**
> Again, this plugin is not prepared for having users, but this is how you'd configure it if you wanted to try it out.

```lua
-- default config:
require("image").setup({
  backend = "kitty",
  integrations = {
    markdown = {
      enabled = true,
      sizing_strategy = "auto",
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  kitty_method = "normal",
  kitty_tmux_write_delay = 5,
})
```

### Backends

- `kitty` (default and with Unicode placeholders, both work inside Tmux)
    - **Using Kitty with the default rendering mode is the best right now.**
    - Works great, is snappy, very few artifacts (on my machine, at least).
- `ueberzug` - backed by [ueberzugpp](https://github.com/jstkdng/ueberzugpp)
    - It's more general, but a bit slower.
    - Now supports multiple images thanks to [@jstkdng](https://github.com/jstkdng/ueberzugpp/issues/74).
    - No cropping yet, so images will get out of bounds, or stretched.
- `sixels` - not implemented yet

### Formats

Currently only PNG files are supported.

- PNG

### Integrations

Currently there's a single integration, for Markdown files, which is enabled by default.
\
Will add more soon and document them here.

- Markdown

## API

```lua
local api = require("image")

local image = api.from_file("path/to/image.png", {
  id = "my_image_id", -- optional, defaults to a random string
  window = 1000, -- optional, binds image to window and its bounds
  buffer = 1000, -- optional, binds image to buffer
  with_virtual_padding = true, -- optional, pads vertically with extmarks
  ...geometry, -- optional, x,y,width,height
})

image.render() -- render image
image.render(geometry) -- update image geometry and render it
image.clear()
```

---

### Thanks

- [@edluffy](https://github.com/edluffy) for [hologram.nvim](https://github.com/edluffy/hologram.nvim) - of which I borrowed a lot of code.
- [@kovidgoyal](https://github.com/kovidgoyal) for [Kitty](https://github.com/kovidgoyal/kitty) - the program I spend most of my time in.
- [@jstkdng](https://github.com/jstkdng) for [ueberzugpp](https://github.com/jstkdng/ueberzugpp) - the revived version of ueberzug.

### The story behind
About few years ago, I took a trip to Emacs land for a few months, to learn Elisp and also research what Org mode is, how it works,
and look for features of interest for my workflow.
I already had my own document syntax, albeit a very simple one, hacked together with Vimscript and a lot
of Regex, and I was looking for ideas to improve it and build features on top of it.

I kept working on my [syntax](https://github.com/3rd/syslang) over the years, rewrote it many times, and today it's a proper Tree-sitter grammar,
that I use for pretty much all my needs, from second-braining to managing my tasks and time.
It's helped me control my ADHD and be productive long before I was diagnosed, and it's still helping me be
so much better than I'd be without it today.

One thing Emacs and Org mode had that I really liked was the ability to embed images in the document.
Of course, we don't *"need"* it, but... I really wanted to have images in my documents.

About 3 years ago I made my [first attempt](https://github.com/3rd/vimage.nvim/tree/master) at solving this problem, but didn't get very far.
\
If you're having similar interests, you might have seem the [vimage.nvim demo video](https://www.youtube.com/watch?v=cnt9mPOjrLg) on YouTube.
\
It was using [ueberzug](https://github.com/seebye/ueberzug), which is now dead, it was buggy, and didn't
handle things like window-relative positioning, attaching images to windows and buffers, folds, etc.
\
Kitty's graphics protocol was a thing, but it didn't work with Tmux, which I'll probably either use forever
or replace it with something of my own.

Now, things have changed, and I'm happy to anounce that rendering images using [Kitty's graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol.html)
from Neovim inside Tmux is working, and it's working pretty well!

My plan for this plugin is to support multiple backends, and provide a few core integrations, and an easy to use API
for other plugin authors to build on top of. There is a lot of logic that deals with positioning, cropping, bounds,
folds, extmarks, etc, that is painful to write, and it's unrealistic to write it from scratch for every plugin that
wants to use images.

