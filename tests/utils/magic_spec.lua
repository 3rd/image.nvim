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

  it("detects JPEG XL codestream and container signatures", function()
    local signatures = {
      "\xFF\x0A",
      "\x00\x00\x00\x0CJXL \x0D\x0A\x87\x0A",
    }

    for _, signature in ipairs(signatures) do
      local path = vim.fn.tempname()
      local file = assert(io.open(path, "wb"))
      file:write(signature)
      file:close()
      assert.are.same("jxl", detect_format(path))
      assert.is_true(require("image/utils/magic").is_image(path))
      vim.fn.delete(path)
    end
  end)

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
