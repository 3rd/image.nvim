# Inline virtual text offset checklist

This file demonstrates the inline-virt-text-offset behavior. Open it in
Neovim with image.nvim and a plugin that injects inline virtual text at the
start of indented content — e.g.
[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
with `indent.enabled = true` and `per_level = 4`.

Without the fix, all images render flush at column 0 (under the indent
virt_text rather than under the alt-text bracket). With the fix, each image's
left edge sits at the visually-indented position of its `![` opener.

## Level 1 — control (no indent virt_text)

Image link starts at column 0, no inline virt_text at the row.
Should render at column 0 with or without the patch.

![h1-control](../test_data/100x100.png)

---

## Level 2 — 4-cell indent virt_text

Content under an H2 gets one `per_level` of inline virt_text. Image link
starts at buffer column 0 (`original_x = 0`); the fix shifts the rendered
image right by 4 cells.

![h2-shifted-by-4](../test_data/100x100.png)

### Level 3 — 8-cell virt_text

![h3-shifted-by-8](../test_data/100x100.png)

#### Level 4 — 12-cell virt_text

![h4-shifted-by-12](../test_data/100x100.png)

---

## Indented (x > 0) — guard skips the adjustment

When the image link sits at a non-zero buffer column (real spaces in the
buffer), the patch's `original_x == 0` guard intentionally bypasses the
adjustment. Treesitter's node:range already reports the indented column
for these, so they need no further shift.

- bullet with image: ![list-l1](../test_data/100x100.png)
  - nested with image: ![list-l2](../test_data/100x100.png)

## What to verify

- [ ] Level 1 image renders at column 0.
- [ ] Level 2 image's left edge sits at column 4 (under the `![`).
- [ ] Level 3 image at column 8.
- [ ] Level 4 image at column 12.
- [ ] List-item images render flush under their respective `![` openers,
      unchanged from previous behavior.
