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
      local lspconfig_defaults = require('lspconfig').util.default_config
      lspconfig_defaults.capabilities = require('blink.cmp').get_lsp_capabilities(lspconfig_defaults.capabilities)
      local fzf = require 'fzf-lua'

      vim.api.nvim_create_autocmd('LspAttach', {
        desc = 'LSP actions',
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
          map('gr', vim.lsp.buf.references, '[G]oto [R]eferences')
          map('gi', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
          map('<leader>ld', fzf.lsp_typedefs, 'Type [D]efinition')
          map('<leader>ls', fzf.lsp_document_symbols, '[L]sp [S]ymbols')
          map('<leader>lS', fzf.lsp_live_workspace_symbols, '[W]orkspace [S]ymbols')
          map('<leader>lc', vim.lsp.buf.rename, '[C]hange var name')
          -- map('K', vim.lsp.buf.hover, 'Loo[K]up')
          --
          vim.keymap.set('n', 'K', function()
            vim.lsp.buf.hover { border = 'none', max_width = 60, max_height = 40 }
          end, { desc = 'LSP Hover' })

          vim.keymap.set('i', '<C-k>', function()
            vim.lsp.buf.signature_help { border = 'none', max_width = 60, max_height = 40 }
          end, { desc = 'LSP Signature Help' })

          map('<leader>la', fzf.lsp_code_actions, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
          map('gs', vim.lsp.buf.signature_help, 'Signature [H]elp')
          vim.keymap.set('i', '<c-s>', vim.lsp.buf.signature_help)

          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
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

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>lh', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, 'Inlay [H]ints')
          end
        end,
      })

      vim.diagnostic.config {
        underline = true,
        update_in_insert = false,
        virtual_text = {
          spacing = 4,
          source = 'if_many',
          prefix = '●',
        },
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

      require('lspconfig').util.default_config.on_init = function(client, _)
        client.server_capabilities.semanticTokensProvider = nil
      end

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
                  typeCheckingMode = 'off',
                  logLevel = 'error',
                  diagnosticSeverityOverrides = {
                    reportAttributeAccessIssue = 'none',
                  },

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
