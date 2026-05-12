local virtual_padding = require("image/utils/virtual_padding")

describe("virtual padding", function()
  describe("get_reserved_lines", function()
    it("uses normal virtual padding when overlap is omitted", function()
      assert.are.same(5, virtual_padding.get_reserved_lines(5, 0, nil))
    end)

    it("reserves render offset when overlap is omitted", function()
      assert.are.same(7, virtual_padding.get_reserved_lines(5, 2, nil))
    end)

    it("clamps omitted-overlap negative offset results at zero", function()
      assert.are.same(0, virtual_padding.get_reserved_lines(2, -4, nil))
    end)

    it("uses normal virtual padding when overlap is zero", function()
      assert.are.same(5, virtual_padding.get_reserved_lines(5, 0, 0))
    end)

    it("reserves render offset when overlap is zero", function()
      assert.are.same(7, virtual_padding.get_reserved_lines(5, 2, 0))
    end)

    it("counts positive overlap from the anchor line", function()
      assert.are.same(5, virtual_padding.get_reserved_lines(5, 0, 1))
    end)

    it("uses normal virtual padding when overlap is fractional", function()
      assert.are.same(5, virtual_padding.get_reserved_lines(5, 0, 1.5))
    end)

    it("removes padding when overlap covers the rendered image", function()
      assert.are.same(0, virtual_padding.get_reserved_lines(5, 0, 6))
    end)

    it("clamps negative offset results at zero", function()
      assert.are.same(0, virtual_padding.get_reserved_lines(2, -4, 0))
    end)
  end)

  describe("get_overlap_scroll_position", function()
    it("does not handle omitted overlap", function()
      assert.is_nil(virtual_padding.get_overlap_scroll_position(4, 6, 10, 5))
    end)

    it("does not handle zero overlap", function()
      assert.is_nil(virtual_padding.get_overlap_scroll_position(4, 6, 10, 5, nil, 0))
    end)

    it("does not handle fractional overlap", function()
      assert.is_nil(virtual_padding.get_overlap_scroll_position(4, 6, 10, 5, nil, 1.5))
    end)

    it("keeps explicit-overlap images visible while covered lines remain", function()
      local absolute_y, scrolled_lines = virtual_padding.get_overlap_scroll_position(4, 6, 10, 5, 0, 5)

      assert.are.same(9, absolute_y)
      assert.are.same(1, scrolled_lines)
    end)

    it("keeps the last covered overlap line visible", function()
      local absolute_y, scrolled_lines = virtual_padding.get_overlap_scroll_position(4, 9, 10, 5, 0, 5)

      assert.are.same(6, absolute_y)
      assert.are.same(4, scrolled_lines)
    end)

    it("uses render offset when calculating overlap scroll position", function()
      local absolute_y, scrolled_lines = virtual_padding.get_overlap_scroll_position(4, 6, 10, 5, 2, 5)

      assert.are.same(11, absolute_y)
      assert.are.same(1, scrolled_lines)
    end)

    it("keeps the last visible image row visible", function()
      local absolute_y, scrolled_lines = virtual_padding.get_overlap_scroll_position(4, 6, 10, 5, -3, 5)

      assert.are.same(6, absolute_y)
      assert.are.same(1, scrolled_lines)
    end)

    it("stops handling once scrolled beyond covered overlap lines", function()
      assert.is_nil(virtual_padding.get_overlap_scroll_position(4, 10, 10, 5, nil, 5))
    end)

    it("stops handling once scrolled beyond visible image rows", function()
      assert.is_nil(virtual_padding.get_overlap_scroll_position(4, 8, 10, 5, -3, 5))
    end)
  end)
end)
