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
      vim.cmd [[cab cc CodeCompanion]]
      vim.keymap.set('n', '<leader>cc', '<cmd>CodeCompanionChat<CR>')
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
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    build = ':Copilot auth',
    event = 'BufReadPost',
    config = function()
      require('copilot').setup {
        suggestion = {
          enabled = true,
          auto_trigger = true,
          hide_during_completion = true,
          keymap = {
            accept = '<Tab>', -- handled by nvim-cmp / blink.cmp
            next = '<M-]>',
            prev = '<M-[>',
          },
        },
        panel = { enabled = false },
      }

      vim.api.nvim_create_autocmd('User', {
        pattern = 'BlinkCmpMenuOpen',
        callback = function()
          vim.b.copilot_suggestion_hidden = true
        end,
      })

      vim.api.nvim_create_autocmd('User', {
        pattern = 'BlinkCmpMenuClose',
        callback = function()
          vim.b.copilot_suggestion_hidden = false
        end,
      })
      vim.keymap.set('n', '<leader>c', '<cmd>Copilot toggle<CR>')
    end,
  },
  { 'giuxtaposition/blink-cmp-copilot' },
}
