local utils = require("image/utils")

---@param state State
local function create_report(state)
  local lines = {}
  local function add(text)
    table.insert(lines, text or "")
  end

  add("# image.nvim report")
  add("")
  add("Make sure you don't leak any personal information before sharing this report.")
  add("")

  -- system
  add("## System Information")
  add("")
  add("```")
  add(string.format("OS: %s", vim.loop.os_uname().sysname))
  add(string.format("Neovim: %s", vim.version()))
  -- pstree
  local function get_parent_pid(pid)
    return vim.fn.system(string.format("ps -o ppid= -p %d", pid)):gsub("%s+", "")
  end
  local function get_process_name(pid)
    return vim.fn.system(string.format("ps -o comm= -p %d", pid)):gsub("%s+", "")
  end
  local pid = tostring(vim.fn.getpid())
  local tree = {}
  while pid and pid ~= "1" and pid ~= "" do
    local name = get_process_name(pid)
    if name ~= "" then table.insert(tree, string.format("%s(%s)", name, pid)) end
    pid = get_parent_pid(pid)
  end
  add(string.format("Process Tree: %s", table.concat(tree, " <- ")))
  -- term
  add(string.format("TERM: %s", os.getenv("TERM")))
  if utils.tmux.is_tmux then
    add(string.format("Tmux: %s", utils.tmux.get_version()))
    local allow_passthrough = vim.fn.system({ "tmux", "show", "-gv", "allow-passthrough" }):gsub("%s+", "")
    add(string.format("Tmux Allow Passthrough: %s", allow_passthrough))
    local visual_activity = vim.fn.system({ "tmux", "show", "-gv", "visual-activity" }):gsub("%s+", "")
    add(string.format("Tmux Visual Activity: %s", visual_activity))
  end
  add("```")
  add("")

  -- configuration
  add("## Plugin Configuration")
  add("")
  add("```json")
  add(utils.json.encode(state.options, 2))
  add("```")
  add("")

  -- processor
  add("## Processor Information")
  add("")
  add("```")
  add(string.format("Active Processor: %s", state.options.processor or "magick_cli"))
  if state.options.processor == "magick_cli" or not state.options.processor then
    add(string.format("ImageMagick CLI Available: %s", vim.fn.executable("convert") == 1))
    if vim.fn.executable("convert") == 1 then
      local version = vim.fn.system("convert -version"):match("Version: ImageMagick ([^\n]+)")
      add(string.format("ImageMagick Version: %s", version))
    end
  elseif state.options.processor == "magick_rock" then
    local has_magick = pcall(require, "magick")
    add(string.format("Magick Rock Available: %s", has_magick))
    if has_magick then
      local magick = require("magick")
      add(string.format("Magick Rock Version: %s", magick.VERSION))
    end
  end
  add("```")
  add("")

  -- backend
  add("## Backend Information")
  add("")
  add("```")
  add(string.format("Active Backend: %s", state.options.backend))
  if state.options.backend == "kitty" then add(string.format("Kitty PID: %s", vim.env.KITTY_PID or "N/A")) end
  add(string.format("Backend Features: %s", vim.inspect(state.backend.features)))
  add("```")
  add("")

  -- images
  add("## Images")
  add("")
  add("```")
  for id, image in pairs(state.images) do
    add(string.format("ID: %s", id))
    add(string.format("  Dimensions: %dx%d", image.image_width, image.image_height))
    add(string.format("  Window: %s", image.window or "N/A"))
    add(string.format("  Buffer: %s", image.buffer or "N/A"))
    add(string.format("  Rendered: %s", image.is_rendered))
    add("")
  end
  add("```")

  -- buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  local content = table.concat(lines, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- window
  local width = 80
  local height = 40
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
  }
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.wo[win].wrap = true

  -- mappings
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", {
    noremap = true,
    silent = true,
  })

  return buf
end

return {
  create = create_report,
}
