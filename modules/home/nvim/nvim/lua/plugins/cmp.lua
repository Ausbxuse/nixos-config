return {
  {
    'saghen/blink.cmp',
    dependencies = {
      {
        'fang2hou/blink-copilot',
        opts = {
          max_completions = 1, -- Global default for max completions
          max_attempts = 2, -- Global default for max attempts
          kind_icon = '',
        },
      },
    },

    version = '*',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      signature = { enabled = true },

      cmdline = { enabled = true },
      completion = {
        menu = {
          winblend = 10, -- WARN: causes different nerfont icon sizes
          auto_show = function(ctx)
            return not vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype())
          end,
          draw = {
            -- columns = { { 'label', 'label_description', gap = 1 }, { 'kind_icon', 'kind', gap = 1 } },
            treesitter = { 'lsp' },
          },
        },
        ghost_text = {
          enabled = true,
        },
        -- auto_show = true,
        -- trigger = { prefetch_on_insert = false },
      },
      -- TODO: better tab for snippets jump
      keymap = {
        preset = 'default',
        ['<Tab>'] = {
          function()
            return require('sidekick').nes_jump_or_apply()
          end,
          function(cmp)
            if cmp.is_menu_visible() then
              return cmp.select_and_accept()
            end
          end,
          'fallback',
        },

        ['<C-s>'] = { 'show', 'show_documentation', 'hide_documentation' },
        -- ['<c-e>'] = { 'snippet_forward', 'fallback' },
        -- ['<c-y>'] = { 'snippet_backward', 'fallback' },
      },

      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = 'mono',
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer', 'copilot' },
        providers = {
          copilot = {
            name = 'copilot',
            module = 'blink-copilot',
            score_offset = 100,
            async = true,
            opts = {
              -- Local options override global ones
              max_completions = 3, -- Override global max_completions

              -- Final settings:
              -- * max_completions = 3
              -- * max_attempts = 2
              -- * all other options are default
            },
          },
        },
      },
    },
    opts_extend = { 'sources.default' },
  },
}
