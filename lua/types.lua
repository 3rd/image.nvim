---@meta

---@class State
---@field backend Backend
---@field options Options

---@class MarkdownIntegrationOptions
---@field enabled boolean
---@field sizing_strategy "none" | "height-from-empty-lines"

---@alias IntegrationOptions MarkdownIntegrationOptions

---@class MarginOptions
---@field top number
---@field right number
---@field bottom number
---@field left number

---@class Options
---@field backend "kitty"|"ueberzug"
---@field integrations { markdown: IntegrationOptions }
---@field margin MarginOptions

---@class Backend
---@field setup? fun(options: Options)
---@field render fun(image_id: string, url: string, x: number, y: number, width: number, height: number)
---@field clear fun(image_id?: string)

---@class IntegrationContext -- wish proper generics were a thing here
---@field options IntegrationOptions
---@field render fun(image_id: string, url: string, x: number, y: number, width: number, height: number)
---@field render_relative_to_window fun(win: Window|number, image_id: string, url: string, x: number, y: number, width: number, height: number): boolean
---@field clear fun(image_id?: string)

---@class Integration
---@field setup? fun(context: IntegrationContext<IntegrationOptions>)

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
