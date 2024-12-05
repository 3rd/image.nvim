local magic = require("image/utils/magic")
local detect_format = magic.detect_format

describe("magic", function()
  local test_cases = {
    {
      file = "tests/test_data/100x100.png",
      expected = "png",
    },
    {
      file = "tests/test_data/512x512.avif",
      expected = "avif",
    },
    {
      file = "tests/test_data/512x512.bmp",
      expected = "bmp",
    },
    {
      file = "tests/test_data/512x512.gif",
      expected = "gif",
    },
    {
      file = "tests/test_data/512x512.heic",
      expected = "heic",
    },
    {
      file = "tests/test_data/512x512.JPEG",
      expected = "jpeg",
    },
    {
      file = "tests/test_data/512x512.jpg",
      expected = "jpeg",
    },
    {
      file = "tests/test_data/512x512.png",
      expected = "png",
    },
    {
      file = "tests/test_data/512x512.webp",
      expected = "webp",
    },
    {
      file = "tests/test_data/512x512.xpm",
      expected = "xpm",
    },
  }

  for _, case in ipairs(test_cases) do
    it(string.format("detects format of %s (%s)", case.file, case.expected), function()
      local result = detect_format(case.file)
      assert.are.same(case.expected, result)
    end)
  end

  it("returns nil for non-existent files", function()
    assert.is_nil(detect_format("tests/test_data/nonexistent.png"))
  end)

  it("returns nil for non-image files", function()
    assert.is_nil(detect_format("tests/test_data/test.txt"))
  end)

  it("handles corrupted image files gracefully", function()
    assert.are.same(detect_format("tests/test_data/corrupted.png"), "png")
  end)

  it("detects actual format despite wrong extension", function()
    assert.are.same(detect_format("tests/test_data/512x512_actually_jpeg.png"), "jpeg")
  end)
end)
