return {
  ---@type LazySpec
  {
    'mikavilpas/yazi.nvim',
    event = 'VeryLazy',
    keys = {
      {
        '<leader>N',
        '<cmd>Yazi<cr>',
        desc = 'Open yazi at the current file',
      },
      {
        '<leader>n',
        '<cmd>Yazi cwd<cr>',
        desc = "Open the file manager in nvim's working directory",
      },
    },
    ---@type YaziConfig
    opts = {
      open_for_directories = true,
      keymaps = {
        show_help = '<f1>',
      },
    },
    config = function(_, opts)
      require('yazi').setup(opts)
    end,
  },
  { 'mbbill/undotree' },
  -- {
  --   'yetone/avante.nvim',
  --   event = 'VeryLazy',
  --   lazy = false,
  --   version = false, -- Set this to "*" to always pull the latest release version, or set it to false to update to the latest code changes.
  --   opts = {
  --     provider = 'claude',
  --     hints = { enabled = false },
  --   },
  --   -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  --   build = 'make',
  --   dependencies = {
  --     'nvim-treesitter/nvim-treesitter',
  --     'nvim-lua/plenary.nvim',
  --     'MunifTanjim/nui.nvim',
  --   },
  -- },
  {
    'oskarrrrrrr/symbols.nvim',
    config = function()
      local r = require 'symbols.recipes'
      require('symbols').setup(r.DefaultFilters, r.AsciiSymbols, {
        -- custom settings here
        -- e.g. hide_cursor = false
        show_details_pop_up = true,
        keymaps = {
          -- Jumps to symbol in the source window.
          ['l'] = 'goto-symbol',
        },
      })
      vim.keymap.set('n', ',s', '<cmd> Symbols<CR>')
      vim.keymap.set('n', ',S', '<cmd> SymbolsClose<CR>')
    end,
  },
  {
    'olimorris/codecompanion.nvim',
    config = function()
      require('codecompanion').setup {
        strategies = {
          chat = {
            adapter = 'anthropic',
          },
          inline = {
            adapter = 'anthropic',
          },
        },
      }
    end,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
  },
  {
    'frankroeder/parrot.nvim',
    dependencies = { 'ibhagwan/fzf-lua', 'nvim-lua/plenary.nvim' },
    -- optionally include "folke/noice.nvim" or "rcarriga/nvim-notify" for beautiful notifications
    config = function()
      require('parrot').setup {
        providers = {
          anthropic = {
            api_key = os.getenv 'ANTHROPIC_API_KEY',
          },
        },
      }
    end,
  },
  {
    'milanglacier/minuet-ai.nvim',
    config = function()
      require('minuet').setup {
        provider = 'claude',

        blink = {
          enable_auto_complete = false,
        },
        -- provider_options = {
        --   claude = {
        --     max_tokens = 512,
        --     model = 'claude-3-5-haiku-20241022',
        --     system = 'see [Prompt] section for the default value',
        --     few_shots = 'see [Prompt] section for the default value',
        --     chat_input = 'See [Prompt Section for default value]',
        --     stream = true,
        --     api_key = 'ANTHROPIC_API_KEY',
        --     optional = {
        --       -- pass any additional parameters you want to send to claude request,
        --       -- e.g.
        --       -- stop_sequences = nil,
        --     },
        --   },
        -- },
      }

      vim.keymap.set('n', '<leader>m', '<cmd>Minuet blink toggle<CR>')
    end,
  },
}
