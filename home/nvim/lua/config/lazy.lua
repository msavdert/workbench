-- lazy.nvim itself is cloned once, during `docker build`. Every other plugin is
-- pinned by lazy-lock.json and restored at build time (`Lazy! restore`), so
-- nothing here reaches the network on start-up.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  -- stylua: ignore
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(vim.env.LAZYPATH or lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- LazyVim extras (lang.*, ai.*, ...) are deliberately not imported: each
    -- one pulls in more plugins and, for lang.*, mason-managed servers. Add a
    -- server to home/mise/config.box.toml and lua/plugins/devbox.lua instead.
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- lazy-lock.json is the pin, not semver tags
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- No update checks: versions change only when lazy-lock.json is updated
  -- deliberately (docs/06-maintenance.md).
  checker = { enabled = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
})
