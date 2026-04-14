return {
  {
    'ibhagwan/fzf-lua',
    -- dependencies = { 'nvim-tree/nvim-web-devicons' },
    keys = {
      { '<leader>fh', function() require('fzf-lua').help_tags() end, desc = '[F]ind [H]elp' },
      { '<leader>fk', function() require('fzf-lua').keymaps() end, desc = '[F]uzzy find [K]eymaps' },
      { '<leader>ff', function() require('fzf-lua').files() end, desc = '[F]uzzy [F]iles' },
      { '<leader>fs', function() require('fzf-lua').grep_cword() end, desc = '[S]earch current [W]ord' },
      { '<leader>fg', function() require('fzf-lua').live_grep() end, desc = '[S]earch by [G]rep' },
      { '<leader>fd', function() require('fzf-lua').diagnostics_workspace() end, desc = '[S]earch [D]iagnostics' },
      { '<leader>fS', function() require('fzf-lua').grep_cWORD() end, desc = '[f]ind [S]earch word' },
      { '<leader>fr', function() require('fzf-lua').oldfiles() end, desc = '[S]earch Recent Files ' },
      { '<leader>o', function() require('fzf-lua').lsp_document_symbols() end, desc = 'Symb[o]ls ' },
      { '<leader>b', function() require('fzf-lua').buffers() end, desc = 'Find existing buffers' },
      { '<leader>/', function() require('fzf-lua').blines() end, desc = '[/] Fuzzily search in current buffer' },
    },
    config = function()
      local fzf = require 'fzf-lua'
      local actions = require 'fzf-lua.actions'
      fzf.setup {
        fzf_colors = {
          false, -- inherit fzf colors that aren't specified below from
          ['scrollbar'] = { 'fg', { 'SignColumn', 'Normal' }, 'bold' },
          ['prompt'] = { 'fg', 'Conditional' },
          ['marker'] = { 'fg', 'Keyword' },
          ['fg'] = { 'fg', 'MsgArea' },
          ['bg'] = { 'bg', 'SpecialKey' },
          ['hl'] = { 'fg', 'Debug' },
          ['fg+'] = { 'fg', 'Normal' },
          ['bg+'] = { 'bg', { 'CursorLine', 'MsgArea' } },
          ['hl+'] = { 'fg', 'Debug' },
          ['info'] = { 'fg', 'PreProc' },
        },
        winopts = {
          file_icons = false,
          height = 0.8,
          width = 1,
          border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
          backdrop = 100,
          preview = {
            border = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
          },
          treesitter = {
            enabled = true,
            fzf_colors = {
              -- ['hl'] = { 'fg', 'Debug' }, -- match colour
              -- ['hl+'] = { 'fg', 'Debug' }, -- selected match
            },
          },
        },
        buffers = {
          previewer = false,
          mru = true,
          winopts = {
            -- height = 0.4,
            row = 1,
            col = 0,
          },
        },
        previewer = {
          border = 'noborder',
        },
        files = {
          previewer = false,
          actions = {
            ['ctrl-g'] = false,
          },
        },
        -- grep = {
        --   actions = {
        --     ['ctrl-g'] = false,
        --     ['ctrl-q'] = actions.file_sel_to_qf,
        --   },
        -- },

        -- winopts = { preview = { layout = 'horizontal' } },
        keymap = {
          fzf = {
            ['ctrl-z'] = 'abort',
            ['ctrl-f'] = 'half-page-down',
            ['ctrl-b'] = 'half-page-up',
            ['ctrl-a'] = 'beginning-of-line',
            ['ctrl-e'] = 'end-of-line',
            ['alt-a'] = 'toggle-all',
            -- Only valid with fzf previewers (bat/cat/git/etc)
            ['f3'] = 'toggle-preview-wrap',
            ['f4'] = 'toggle-preview',
            ['ctrl-d'] = 'preview-page-down',
            ['ctrl-u'] = 'preview-page-up',
            ['ctrl-q'] = 'select-all+accept',
          },
        },
        oldfiles = {
          previewer = false,
        },
        blines = {
          file_icons = false,
          previewer = false,
          show_bufname = false, -- display buffer name
          show_unloaded = false, -- show unloaded buffers
        },
      }
    end,
  },
}
