---@meta

---@class API
---@field setup fun(options?: Options)
---@field from_file fun(path: string, options?: ImageOptions): Image
---@field clear fun(id?: string)
---@field get_images fun(opts?: { window?: number, buffer?: number }): Image[]

---@class State
---@field backend Backend
---@field options Options
---@field images { [string]: Image }
---@field extmarks_namespace any

---@class MarkdownIntegrationOptions
---@field enabled boolean
---@field sizing_strategy "auto"|"height-from-empty-lines"

---@alias IntegrationOptions MarkdownIntegrationOptions

---@class Options
---@field backend "kitty"|"ueberzug"
---@field integrations { markdown: IntegrationOptions }
---@field max_width? number
---@field max_height? number
---@field max_width_window_percentage? number
---@field max_height_window_percentage? number

---@class Backend
---@field state State
---@field setup fun(state: State)
---@field render fun(image: Image, x: number, y: number, width?: number, height?: number)
---@field clear fun(id?: string)

---@class ImageGeometry
---@field x? number
---@field y? number
---@field width? number
---@field height? number

---@class ImageOptions: ImageGeometry
---@field id? string
---@field window? number
---@field buffer? number
---@field with_virtual_padding? boolean

---@class Image
---@field id string
---@field internal_id number
---@field path string
---@field window? number
---@field buffer? number
---@field with_virtual_padding? boolean
---@field geometry ImageGeometry
---@field rendered_geometry ImageGeometry
---@field get_dimensions fun(): { width: number, height: number }
---@field render fun(geometry?: ImageGeometry)
---@field clear fun()

---@class IntegrationContext -- wish proper generics were a thing here
---@field options IntegrationOptions
---@field api API

---@class Integration
---@field setup? fun(api: API, options: IntegrationOptions)

---@class Window
---@field id number
---@field buffer number
---@field x number
---@field y number
---@field width number
---@field height number
---@field scroll_x number
---@field scroll_y number
---@field is_visible boolean

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
