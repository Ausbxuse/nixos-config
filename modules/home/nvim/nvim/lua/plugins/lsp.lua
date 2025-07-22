-- Adds custom words to lsp
local words = {}
local spellfile = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add'
local file = io.open(spellfile, 'r')
if file then
  for line in file:lines() do
    table.insert(words, line)
  end
  file:close()
else
  print('Error: Unable to open spell file at ' .. spellfile)
end

-- local lspconfig_defaults = require('lspconfig').util.default_config
-- lspconfig_defaults.capabilities = require('blink.cmp').get_lsp_capabilities(lspconfig_defaults.capabilities)

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client:supports_method 'textDocument/completion' then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
    client.server_capabilities.semanticTokensProvider = nil
  end,
})
local fzf = require 'fzf-lua'

vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local map = function(keys, func, desc, mode)
      mode = mode or 'n'
      vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
    end

    map('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
    map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
    map('<leader>ld', fzf.lsp_typedefs, 'Type [D]efinition')
    map('<leader>lS', fzf.lsp_live_workspace_symbols, '[W]orkspace [S]ymbols')
    vim.keymap.set('n', '<leader>lq', vim.diagnostic.setloclist, { desc = 'Open diagnostic Quickfix [l]ist' })
    vim.keymap.set('n', 'K', function()
      vim.lsp.buf.hover { border = 'none', max_width = 60, max_height = 40 }
    end, { desc = 'LSP Hover' })

    vim.keymap.set('i', '<C-k>', function()
      vim.lsp.buf.signature_help { border = 'none', max_width = 60, max_height = 40 }
    end, { desc = 'LSP Signature Help' })

    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
      local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buffer = event.buf,
        group = highlight_augroup,
        callback = vim.lsp.buf.document_highlight,
      })

      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = event.buf,
        group = highlight_augroup,
        callback = vim.lsp.buf.clear_references,
      })

      vim.api.nvim_create_autocmd('LspDetach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
        callback = function(event2)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
        end,
      })
    end

    if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
      map('<leader>lh', function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
      end, 'Inlay [H]ints')
    end
  end,
})

vim.diagnostic.config {
  underline = true,
  update_in_insert = false,

  virtual_lines = {
    -- Only show virtual line diagnostics for the current cursor line
    current_line = true,
  },
  -- virtual_text = {
  --   spacing = 4,
  --   source = 'if_many',
  --   prefix = '●',
  -- },
  signs = {
    active = true, -- turn _on_ your custom signs
    text = { -- here are your icons
      [vim.diagnostic.severity.ERROR] = '',
      [vim.diagnostic.severity.WARN] = '',
      [vim.diagnostic.severity.INFO] = '',
      [vim.diagnostic.severity.HINT] = '',
    },
    texthl = { -- make sure the highlight groups line up, too
      [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
      [vim.diagnostic.severity.WARN] = 'DiagnosticWarn',
      [vim.diagnostic.severity.INFO] = 'DiagnosticInfo',
      [vim.diagnostic.severity.HINT] = 'DiagnosticHint',
    },
    numhl = {
      [vim.diagnostic.severity.WARN] = 'DiagnosticWarn',
      [vim.diagnostic.severity.ERROR] = 'DiagnosticError',
      [vim.diagnostic.severity.INFO] = 'DiagnosticInfo',
      [vim.diagnostic.severity.HINT] = 'DiagnosticHint',
    },
  },
  -- signs = true,
  severity_sort = true,
}
-- require('lspconfig').harper_ls.setup {
--   filetypes = { 'markdown' },
--   settings = {
--     ['harper-ls'] = {
--       -- isolateEnglish = true,
--       markdown = {
--         ignore_link_title = true,
--       },
--       userDictPath = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add',
--       linters = {
--         spell_check = true,
--         spelled_numbers = false,
--         an_a = true,
--         sentence_capitalization = true,
--         unclosed_quotes = true,
--         wrong_quotes = true,
--         long_sentences = true,
--         repeated_words = true,
--         spaces = true,
--         matcher = true,
--         correct_number_suffix = true,
--         number_suffix_capitalization = true,
--         multiple_sequential_pronouns = true,
--         linking_verbs = true,
--         avoid_curses = true,
--         terminating_conjunctions = true,
--       },
--     },
--   },
-- }

return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  {
    'dundalek/lazy-lsp.nvim',
    enabled = true,
    dependencies = {
      'neovim/nvim-lspconfig',
      'Saghen/blink.cmp',
    },
    config = function()
      require('lazy-lsp').setup {
        excluded_servers = {
          'ruff_lsp',
          'ccls',
          'zk',
          'ts_ls',
          'buf_ls',
          'c3_lsp',
          'sourcekit',
        },
        preferred_servers = {
          markdown = { 'ltex' },
          python = { 'basedpyright' },
          netrw = {},
        },
        prefer_local = true,
        -- Default config passed to all servers to specify on_attach callback and other options.
        default_config = {
          flags = {
            debounce_text_changes = 150,
          },
        },
        -- Override config for specific servers that will passed down to lspconfig setup.
        -- Note that the default_config will be merged with this specific configuration so you don't need to specify everything twice.
        configs = {
          basedpyright = {
            settings = {
              basedpyright = {
                analysis = {
                  typeCheckingMode = 'basic',
                  logLevel = 'error',
                  -- diagnosticSeverityOverrides = {
                  --   reportAttributeAccessIssue = 'none',
                  -- },

                  inlayHints = { variableTypes = true, functionReturnTypes = true },
                },
              },
              hints = {
                enable = true,
              },
              codeLens = {
                enable = true,
              },
            },
          },
          lua_ls = {
            settings = {
              Lua = {
                workspace = {
                  checkThirdParty = false,
                },
                hint = {
                  enable = true,
                },
                completion = {
                  displayContext = 1,
                  callSnippet = 'Both',
                },
              },
            },
          },
          ltex = {
            settings = {
              ltex = {
                enabled = {
                  'bibtex',
                  'gitcommit',
                  'markdown',
                  'org',
                  'tex',
                  'restructuredtext',
                  'rsweave',
                  'latex',
                  'quarto',
                  'rmd',
                  'context',
                  'html',
                  'xhtml',
                },
                workspace = {
                  checkThirdParty = false,
                },
                codeLens = {
                  enable = true,
                },
                completion = {
                  callSnippet = 'Replace',
                },
                dictionary = {
                  ['en-US'] = words,
                },
              },
            },
          },
        },
      }
    end,
  },
}
