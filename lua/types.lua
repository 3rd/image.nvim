---@meta

---@class State
---@field backend Backend
---@field integrations Integration[]
---@field options Options

---@class MarkdownIntegrationOptions
---@field enabled boolean

---@class IntegrationOptions
---@field markdown MarkdownIntegrationOptions

---@class MarginOptions
---@field top number
---@field right number
---@field bottom number
---@field left number

---@class Options
---@field backend "kitty"|"ueberzug"
---@field integrations IntegrationOptions
---@field margin MarginOptions

---@class Backend
---@field setup fun()
---@field render fun(image_id: string, url: string, x: number, y: number, width: number, height: number)
---@field clear fun(image_id?: string)

---@class Integration
---@field setup fun(options: Options)
---@field validate fun(buf: number): boolean
---@field get_buffer_images fun(buf: number): Image[] -- TODO remove

---@class Window
---@field id number
---@field buf number
---@field x number
---@field y number
---@field width number
---@field height number
---@field scroll_x number
---@field scroll_y number

---@class Image
---@field node any
---@field range {start_row: number, start_col: number, end_row: number, end_col: number}
---@field url string
---@field width? number
---@field height? number
