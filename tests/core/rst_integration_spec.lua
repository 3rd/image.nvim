local unload_image_modules = function()
  for module_name in pairs(package.loaded) do
    if module_name == "image" or module_name:match("^image/") then package.loaded[module_name] = nil end
  end
end

describe("rst integration defaults", function()
  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "image.nvim")
    local namespace = vim.api.nvim_get_namespaces()["image.nvim"]
    if namespace then pcall(vim.api.nvim_set_decoration_provider, namespace, {}) end
    unload_image_modules()
  end)

  it("loads rst when integration options override only its rendering settings", function()
    local configured
    package.loaded["image/integrations/rst"] = {
      setup = function(_, options)
        configured = options
      end,
    }

    local image = require("image")
    image.setup({
      integrations = {
        markdown = { enabled = false },
        asciidoc = { enabled = false },
        typst = { enabled = false },
        neorg = { enabled = false },
        syslang = { enabled = false },
        html = { enabled = false },
        css = { enabled = false },
        org = { enabled = false },
        rst = { only_render_image_at_cursor = true },
      },
      hijack_file_patterns = {},
    })

    assert.is_true(configured ~= nil)
    assert.is_true(configured.enabled)
    assert.is_true(configured.only_render_image_at_cursor)
  end)
end)
