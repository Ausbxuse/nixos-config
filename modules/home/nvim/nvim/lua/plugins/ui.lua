local home = vim.fn.expand '$HOME'

local function set_path(file_path)
  local file_stat = vim.loop.fs_stat(file_path)
  local path_variable = file_stat and file_path or nil
  return path_variable
end
return {
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    ---@module "ibl"
    ---@type ibl.config
    opts = {},
    config = function()
      require('ibl').setup {
        indent = {
          char = '▏',
        },
        scope = {
          enabled = true,
          show_start = false,
          show_end = false,
          char = '▏',
        },
      }
    end,
  },
  -- lua/plugins/treesitter.lua (or wherever your lazy specs live)
  {
    {
      'nvim-treesitter/nvim-treesitter',
      branch = 'main',
      lazy = false, -- main branch: "does not support lazy-loading" :contentReference[oaicite:5]{index=5}
      build = ':TSUpdate',
      config = function()
        local ts = require 'nvim-treesitter'

        -- Optional: match the README example install_dir :contentReference[oaicite:6]{index=6}
        ts.setup {
          install_dir = vim.fn.stdpath 'data' .. '/site',
        }

        -- Equivalent of your old ensure_installed + auto_install:
        -- install() is a no-op for already-installed parsers. :contentReference[oaicite:7]{index=7}
        ts.install {
          'bash',
          'c',
          'diff',
          'html',
          'lua',
          'luadoc',
          'markdown',
          'markdown_inline',
          'query',
          'vim',
          'vimdoc',
          'python',
          'cpp',
          'just',
          'nix',
          'tmux',
          'yaml',
        }

        -- Enable TS highlighting (provided by Neovim) :contentReference[oaicite:8]{index=8}
        vim.api.nvim_create_autocmd('FileType', {
          pattern = {
            'bash',
            'sh',
            'zsh',
            'c',
            'diff',
            'html',
            'lua',
            'markdown',
            'vim',
            'python',
            'cpp',
            'nix',
            'tmux',
            'yaml',
            'just',
          },
          callback = function()
            vim.treesitter.start()
          end,
        })

        -- Optional: TS indentation (experimental; provided by nvim-treesitter main) :contentReference[oaicite:9]{index=9}
        vim.api.nvim_create_autocmd('FileType', {
          pattern = {
            'bash',
            'sh',
            'zsh',
            'c',
            'html',
            'lua',
            'python',
            'cpp',
            'nix',
            'yaml',
            'just',
            'vim',
            'tmux',
            'markdown',
          },
          callback = function()
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end,
        })
      end,
    },

    {
      'nvim-treesitter/nvim-treesitter-textobjects',
      branch = 'main',
      lazy = false,
      init = function()
        -- From textobjects README main branch :contentReference[oaicite:10]{index=10}
        vim.g.no_plugin_maps = true
      end,
      config = function()
        -- Configure behavior (lookahead, set_jumps, etc.) :contentReference[oaicite:11]{index=11}
        require('nvim-treesitter-textobjects').setup {
          select = {
            lookahead = true,
            include_surrounding_whitespace = false,
          },
          move = {
            set_jumps = true,
          },
        }

        -- === SELECT keymaps (your mappings) ===
        local sel = require 'nvim-treesitter-textobjects.select'
        local function xomap(lhs, capture, group)
          vim.keymap.set({ 'x', 'o' }, lhs, function()
            sel.select_textobject(capture, group)
          end)
        end

        xomap('ah', '@block.outer', 'textobjects')
        xomap('ih', '@block.inner', 'textobjects')
        xomap('af', '@function.outer', 'textobjects')
        xomap('if', '@function.inner', 'textobjects')
        xomap('ac', '@class.outer', 'textobjects')
        xomap('ic', '@class.inner', 'textobjects')
        xomap('ai', '@conditional.outer', 'textobjects')
        xomap('ii', '@conditional.inner', 'textobjects')
        xomap('al', '@loop.outer', 'textobjects')
        xomap('il', '@loop.inner', 'textobjects')
        xomap('as', '@local.scope', 'locals') -- locals group example :contentReference[oaicite:12]{index=12}

        -- === MOVE keymaps (your mappings) ===
        local mv = require 'nvim-treesitter-textobjects.move'
        local function nxo(lhs, fn)
          vim.keymap.set({ 'n', 'x', 'o' }, lhs, fn)
        end

        nxo(']f', function()
          mv.goto_next_start('@function.outer', 'textobjects')
        end)
        nxo(']h', function()
          mv.goto_next_start('@block.outer', 'textobjects')
        end)
        nxo(']c', function()
          mv.goto_next_start('@class.outer', 'textobjects')
        end)
        nxo(']i', function()
          mv.goto_next_start('@conditional.outer', 'textobjects')
        end)
        nxo(']l', function()
          mv.goto_next_start({ '@loop.inner', '@loop.outer' }, 'textobjects')
        end)

        nxo(']F', function()
          mv.goto_next_end('@function.outer', 'textobjects')
        end)
        nxo(']H', function()
          mv.goto_next_end('@block.outer', 'textobjects')
        end)
        nxo(']C', function()
          mv.goto_next_end('@class.outer', 'textobjects')
        end)
        nxo(']I', function()
          mv.goto_next_end('@conditional.outer', 'textobjects')
        end)
        nxo(']L', function()
          mv.goto_next_end({ '@loop.inner', '@loop.outer' }, 'textobjects')
        end)

        nxo('[f', function()
          mv.goto_previous_start('@function.outer', 'textobjects')
        end)
        nxo('[h', function()
          mv.goto_previous_start('@block.outer', 'textobjects')
        end)
        nxo('[c', function()
          mv.goto_previous_start('@class.outer', 'textobjects')
        end)
        nxo('[i', function()
          mv.goto_previous_start('@conditional.outer', 'textobjects')
        end)
        nxo('[l', function()
          mv.goto_previous_start({ '@loop.inner', '@loop.outer' }, 'textobjects')
        end)

        nxo('[F', function()
          mv.goto_previous_end('@function.outer', 'textobjects')
        end)
        nxo('[H', function()
          mv.goto_previous_end('@block.outer', 'textobjects')
        end)
        nxo('[C', function()
          mv.goto_previous_end('@class.outer', 'textobjects')
        end)
        nxo('[I', function()
          mv.goto_previous_end('@conditional.outer', 'textobjects')
        end)
        nxo('[L', function()
          mv.goto_previous_end({ '@loop.inner', '@loop.outer' }, 'textobjects')
        end)
      end,
    },
  },
  {
    'catgoose/nvim-colorizer.lua',
    event = 'VeryLazy',
    opts = { -- set to setup table
      lazy_load = true,
      user_default_options = {
        names = false,
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    config = function()
      require('treesitter-context').setup {
        enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
        multiwindow = false, -- Enable multiwindow support.
        max_lines = 2, -- How many lines the window should span. Values <= 0 mean no limit.
        min_window_height = 0, -- Minimum editor window height to enable context. Values <= 0 mean no limit.
        line_numbers = true,
        multiline_threshold = 20, -- Maximum number of lines to show for a single context
        trim_scope = 'inner', -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
        mode = 'cursor', -- Line used to calculate context. Choices: 'cursor', 'topline'
        -- Separator between context and content. Should be a single character string, like '-'.
        -- When separator is set, the context will only show up when there are at least 2 lines above cursorline.
        separator = nil,
        zindex = 20, -- The Z-index of the context window
        on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
      }
    end,
  },
  {
    'ausbxuse/snappy.nvim',
    priority = 2000, -- Make sure to load this before all the other start plugins.
    dir = set_path(home .. '/src/public/snappy.nvim'),
    init = function()
      vim.cmd.colorscheme 'snappy'
    end,
    config = function()
      require('snappy').setup()
    end,
  },
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'eandrju/cellular-automaton.nvim' },
  {
    'm4xshen/hardtime.nvim',
    lazy = false,
    opts = {},
  },
  {
    'serhez/bento.nvim',
    opts = {
      main_keymap = '\\', -- Main toggle/expand key
    },
  },
}
