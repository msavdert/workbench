-- The one place LazyVim's defaults are adjusted for the box.
--
-- One source per setting: language servers and formatters come from
-- home/mise/config.box.toml, not from mason. Adding one = one line there +
-- one entry below.
return {
  -- mason downloads binaries into ~/.local/share/nvim at runtime, outside
  -- mise and outside this repository, so a rebuilt box would fetch them
  -- again unversioned. Disabled; nvim-lspconfig then uses whatever is on $PATH.
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  -- Not needed here: zellij owns tabs/sessions, ripgrep + sed own
  -- project-wide replace, and the cmdline/notification UI is left native.
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/persistence.nvim", enabled = false },
  { "MagicDuck/grug-far.nvim", enabled = false },
  { "folke/noice.nvim", enabled = false },
  { "windwp/nvim-ts-autotag", enabled = false },
  -- One theme family everywhere (docs/00-vision.md D16): catppuccin, which
  -- picks latte or mocha from 'background'; nvim 0.10+ sets that from the
  -- terminal (OSC 11), so the editor follows Ghostty light/dark. nui.nvim only
  -- served noice.
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
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
