return {
  {
    'saghen/blink.cmp',
    dependencies = 'rafamadriz/friendly-snippets',

    version = '*',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      signature = { enabled = true },
      completion = {
        menu = {
          winblend = 10,
          auto_show = function(ctx)
            return not vim.tbl_contains({ '/', '?' }, vim.fn.getcmdtype())
          end,
          draw = {
            columns = { { 'label', 'label_description', gap = 1 }, { 'kind_icon', 'kind', gap = 1 } },
            treesitter = { 'lsp' },
          },
        },
        ghost_text = {
          enabled = true,
        },
        trigger = { prefetch_on_insert = false },
      },
      keymap = {
        preset = 'default',
        ['<Tab>'] = {
          function(cmp)
            if cmp.snippet_active() then
              return cmp.accept()
            else
              return cmp.select_and_accept()
            end
          end,
          'fallback',
        },
        ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
        ['<c-e>'] = { 'snippet_forward', 'fallback' },
        ['<c-y>'] = { 'snippet_backward', 'fallback' },
        -- ['<A-y>'] = require('minuet').make_blink_map(),
      },

      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = 'mono',
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer', 'minuet' },
        providers = {
          minuet = {
            name = 'minuet',
            module = 'minuet.blink',
            score_offset = 8,
          },
        },
      },
    },
    opts_extend = { 'sources.default' },
  },
}
