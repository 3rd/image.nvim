local dimensions = require("image/utils/dimensions")
local get_dimensions = dimensions.get_dimensions

describe("dimensions", function()
  local test_cases = {
    {
      file = "tests/test_data/100x100.png",
      expected = { width = 100, height = 100 },
      name = "PNG (small)",
    },
    {
      file = "tests/test_data/256x256.ico",
      expected = { width = 256, height = 256 },
      name = "ICO",
    },
    {
      file = "tests/test_data/256x256.png",
      expected = { width = 256, height = 256 },
      name = "PNG (medium)",
    },
    {
      file = "tests/test_data/512x512.avif",
      expected = { width = 512, height = 512 },
      name = "AVIF",
    },
    {
      file = "tests/test_data/512x512.bmp",
      expected = { width = 512, height = 512 },
      name = "BMP",
    },
    {
      file = "tests/test_data/512x512.gif",
      expected = { width = 512, height = 512 },
      name = "GIF",
    },
    {
      file = "tests/test_data/512x512.heic",
      expected = { width = 512, height = 512 },
      name = "HEIC",
    },
    {
      file = "tests/test_data/512x512.JPEG",
      expected = { width = 512, height = 512 },
      name = "JPEG (uppercase)",
    },
    {
      file = "tests/test_data/512x512.jpg",
      expected = { width = 512, height = 512 },
      name = "JPEG (lowercase)",
    },
    {
      file = "tests/test_data/512x512.png",
      expected = { width = 512, height = 512 },
      name = "PNG (large)",
    },
    {
      file = "tests/test_data/512x512.webp",
      expected = { width = 512, height = 512 },
      name = "WebP",
    },
    {
      file = "tests/test_data/512x512.xpm",
      expected = { width = 512, height = 512 },
      name = "XPM",
    },
  }

  -- Standard format tests
  for _, case in ipairs(test_cases) do
    it(string.format("detects dimensions of %s (%s)", case.file, case.name), function()
      local result = get_dimensions(case.file)
      assert.are.same(case.expected, result)
    end)
  end

  -- Special cases
  it("returns nil for SVG files (not supported)", function()
    assert.is_nil(get_dimensions("tests/test_data/512x512.svg"))
  end)

  it("detects actual format despite wrong extension", function()
    local result = get_dimensions("tests/test_data/512x512_actually_jpeg.png")
    assert.are.same({ width = 512, height = 512 }, result)
  end)

  -- Error cases
  it("returns nil for non-existent files", function()
    assert.is_nil(get_dimensions("tests/test_data/nonexistent.png"))
  end)

  it("returns nil for non-image files", function()
    assert.is_nil(get_dimensions("tests/test_data/test.txt"))
  end)

  it("handles corrupted image files gracefully", function()
    assert.is_nil(get_dimensions("tests/test_data/corrupted.png"))
  end)
end)
