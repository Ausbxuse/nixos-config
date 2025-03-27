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
        -- Providers must be explicitly added to make them available.
        providers = {
          anthropic = {
            api_key = os.getenv 'ANTHROPIC_API_KEY',
          },
          gemini = {
            api_key = os.getenv 'GEMINI_API_KEY',
          },
          groq = {
            api_key = os.getenv 'GROQ_API_KEY',
          },
          mistral = {
            api_key = os.getenv 'MISTRAL_API_KEY',
          },
          pplx = {
            api_key = os.getenv 'PERPLEXITY_API_KEY',
          },
          -- provide an empty list to make provider available (no API key required)
          ollama = {},
          openai = {
            api_key = os.getenv 'OPENAI_API_KEY',
          },
          github = {
            api_key = os.getenv 'GITHUB_TOKEN',
          },
          nvidia = {
            api_key = os.getenv 'NVIDIA_API_KEY',
          },
          xai = {
            api_key = os.getenv 'XAI_API_KEY',
          },
        },
      }
    end,
  },
  {
    'milanglacier/minuet-ai.nvim',
    config = function()
      require('minuet').setup {
        -- Your configuration options here
      }
    end,
  },
}
