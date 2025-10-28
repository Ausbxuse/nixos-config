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
      vim.keymap.set('n', '<leader>s', '<cmd>SymbolsToggle<CR>')
    end,
  },
  {
    'olimorris/codecompanion.nvim',
    enabled = false,
    config = function()
      vim.cmd [[cab cc CodeCompanion]]
      vim.keymap.set('n', '<leader>cc', '<cmd>CodeCompanionChat<CR>')
      require('codecompanion').setup {
        strategies = {
          chat = {
            adapter = {
              name = 'gemini',
              model = 'gemini-2.5-flash',
            },
          },
          inline = {
            adapter = 'gemini',
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
    event = 'InsertEnter',
    config = function()
      require('copilot').setup {

        filetypes = {
          yaml = false, -- allow specific filetype
          -- typescript = true, -- allow specific filetype
          -- ["*"] = false, -- disable for all other filetypes and ignore default `filetypes`
        },
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
  {
    'chomosuke/typst-preview.nvim',
    config = function()
      require('typst-preview').setup {
        -- Setting this true will enable logging debug information to
        -- `vim.fn.stdpath 'data' .. '/typst-preview/log.txt'`
        debug = false,

        -- Custom format string to open the output link provided with %s
        -- Example: open_cmd = 'firefox %s -P typst-preview --class typst-preview'
        open_cmd = nil,

        -- Custom port to open the preview server. Default is random.
        -- Example: port = 8000
        port = 0,

        -- Setting this to 'always' will invert black and white in the preview
        -- Setting this to 'auto' will invert depending if the browser has enable
        -- dark mode
        -- Setting this to '{"rest": "<option>","image": "<option>"}' will apply
        -- your choice of color inversion to images and everything else
        -- separately.
        invert_colors = 'never',

        -- Whether the preview will follow the cursor in the source file
        follow_cursor = true,

        -- Provide the path to binaries for dependencies.
        -- Setting this will skip the download of the binary by the plugin.
        -- Warning: Be aware that your version might be older than the one
        -- required.
        dependencies_bin = {
          ['tinymist'] = nil,
          ['websocat'] = nil,
        },

        -- A list of extra arguments (or nil) to be passed to previewer.
        -- For example, extra_args = { "--input=ver=draft", "--ignore-system-fonts" }
        extra_args = nil,

        -- This function will be called to determine the root of the typst project
        get_root = function(path_of_main_file)
          local root = os.getenv 'TYPST_ROOT'
          if root then
            return root
          end
          return vim.fn.fnamemodify(path_of_main_file, ':p:h')
        end,

        -- This function will be called to determine the main file of the typst
        -- project.
        get_main_file = function(path_of_buffer)
          return path_of_buffer
        end,
      }
    end,
  },
  {
    'folke/sidekick.nvim',
    opts = {
      -- add any options here
      cli = {
        mux = {
          backend = 'tmux',
          enabled = true,
        },
      },
    },
  -- stylua: ignore
    keys = {
      {
        "<tab>",
        function()
          -- if there is a next edit, jump to it, otherwise apply it if any
          if not require("sidekick").nes_jump_or_apply() then
            return "<Tab>" -- fallback to normal tab
          end
        end,
        expr = true,
        desc = "Goto/Apply Next Edit Suggestion",
      },
      -- {
      --   "<leader>aa",
      --   function() require("sidekick.cli").toggle() end,
      --   desc = "Sidekick Toggle CLI",
      -- },
      -- {
      --   "<leader>as",
      --   function() require("sidekick.cli").select() end,
      --   -- Or to select only installed tools:
      --   -- require("sidekick.cli").select({ filter = { installed = true } })
      --   desc = "Select CLI",
      -- },
      -- {
      --   "<leader>at",
      --   function() require("sidekick.cli").send({ msg = "{this}" }) end,
      --   mode = { "x", "n" },
      --   desc = "Send This",
      -- },
      -- {
      --   "<leader>av",
      --   function() require("sidekick.cli").send({ msg = "{selection}" }) end,
      --   mode = { "x" },
      --   desc = "Send Visual Selection",
      -- },
      -- {
      --   "<leader>ap",
      --   function() require("sidekick.cli").prompt() end,
      --   mode = { "n", "x" },
      --   desc = "Sidekick Select Prompt",
      -- },
      -- {
      --   "<c-;>",
      --   function() require("sidekick.cli").focus() end,
      --   mode = { "n", "x", "i", "t" },
      --   desc = "Sidekick Switch Focus",
      -- },
      -- -- Example of a keybinding to open Claude directly
      -- {
      --   "<leader>ac",
      --   function() require("sidekick.cli").toggle({ name = "claude", focus = true }) end,
      --   desc = "Sidekick Toggle Claude",
      -- },
    },
  },
}
