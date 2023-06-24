---@meta

---@class State
---@field backend Backend
---@field options Options

---@class MarkdownIntegrationOptions
---@field enabled boolean
---@field sizing_strategy "none"|"height-from-empty-lines"

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

---@class KittyControlConfig
---@field action "t"|"T"|"p"|"d"|"f"|"c"|"a"|"q"
---@field image_id string|number
---@field image_number number
---@field placement_id string|number
---@field quiet 0|1|2
---@field transmit_format 32|24|100
---@field transmit_medium "d"|"f"|"t"|"s"
---@field transmit_more 0|1
---@field transmit_width number
---@field transmit_height number
---@field transmit_file_size number
---@field transmit_file_offset number
---@field transmit_compression 0|1
---@field display_x number
---@field display_y number
---@field display_width number
---@field display_height number
---@field display_x_offset number
---@field display_y_offset number
---@field display_columns number
---@field display_rows number
---@field display_cursor_policy 0|1
---@field display_virtual_placeholder 0|1
---@field display_zindex number
---@field display_delete "a"|"i"|"p"
