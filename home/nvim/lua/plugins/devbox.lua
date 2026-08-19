-- The one place LazyVim's defaults are adjusted for the devbox.
--
-- Rule (CLAUDE.md invariant 1): nothing is downloaded after `docker build`.
-- Language servers and formatters therefore come from home/mise/config.box.toml,
-- not from mason. Adding one = one line in devbox.toml + one entry below.
return {
  -- mason downloads binaries into ~/.local/share/nvim at runtime; that
  -- directory is not persisted, so every container recreation would fetch
  -- them again. Disabled; nvim-lspconfig then uses whatever is on $PATH.
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  -- Not needed here: zellij owns tabs/sessions, ripgrep + sed own
  -- project-wide replace, and the cmdline/notification UI is left native.
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/persistence.nvim", enabled = false },
  { "MagicDuck/grug-far.nvim", enabled = false },
  { "folke/noice.nvim", enabled = false },
  { "windwp/nvim-ts-autotag", enabled = false },
  -- One theme (tokyonight, matching the shell/statusline HUD); nui.nvim only
  -- served noice.
  { "catppuccin/nvim", name = "catppuccin", enabled = false },
  { "MunifTanjim/nui.nvim", enabled = false },

  -- Servers installed by mise. lua_ls is LazyVim's default and stays.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        yamlls = {},
      },
    },
  },
}
