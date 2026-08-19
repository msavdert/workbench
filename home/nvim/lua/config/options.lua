-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

opt.relativenumber = true -- Relative line numbers
opt.number = true -- Print line number

-- Better search
opt.ignorecase = true
opt.smartcase = true

-- Appearance
opt.termguicolors = true
opt.signcolumn = "yes"

-- Split behavior
opt.splitright = true
opt.splitbelow = true

-- Clipboard integration
opt.clipboard = "unnamedplus"

-- Clipboard over OSC 52.
--
-- Only when there is no local clipboard to talk to - i.e. on the box, over
-- ssh. Forcing OSC 52 on a local machine hijacks yanks away
-- from pbcopy/wl-copy and breaks paste, because most terminals refuse OSC 52
-- *reads* for security reasons.
local function is_remote()
  return vim.env.SSH_TTY ~= nil
    or vim.env.SSH_CONNECTION ~= nil
    or vim.fn.filereadable("/.dockerenv") == 1
end

if is_remote() then
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
end


