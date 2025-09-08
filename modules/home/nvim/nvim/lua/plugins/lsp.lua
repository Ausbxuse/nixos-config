-- -- Adds custom words to lsp
-- local words = {}
-- local spellfile = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add'
-- local file = io.open(spellfile, 'r')
-- if file then
--   for line in file:lines() do
--     table.insert(words, line)
--   end
--   file:close()
-- else
--   print('Error: Unable to open spell file at ' .. spellfile)
-- end
--
-- -- local lspconfig_defaults = require('lspconfig').util.default_config
-- -- lspconfig_defaults.capabilities = require('blink.cmp').get_lsp_capabilities(lspconfig_defaults.capabilities)
--
-- vim.api.nvim_create_autocmd('LspAttach', {
--   callback = function(ev)
--     local client = vim.lsp.get_client_by_id(ev.data.client_id)
--     if client:supports_method 'textDocument/completion' then
--       vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
--     end
--     client.server_capabilities.semanticTokensProvider = nil
--   end,
-- })
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

-- -- require('lspconfig').harper_ls.setup {
-- --   filetypes = { 'markdown' },
-- --   settings = {
-- --     ['harper-ls'] = {
-- --       -- isolateEnglish = true,
-- --       markdown = {
-- --         ignore_link_title = true,
-- --       },
-- --       userDictPath = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add',
-- --       linters = {
-- --         spell_check = true,
-- --         spelled_numbers = false,
-- --         an_a = true,
-- --         sentence_capitalization = true,
-- --         unclosed_quotes = true,
-- --         wrong_quotes = true,
-- --         long_sentences = true,
-- --         repeated_words = true,
-- --         spaces = true,
-- --         matcher = true,
-- --         correct_number_suffix = true,
-- --         number_suffix_capitalization = true,
-- --         multiple_sequential_pronouns = true,
-- --         linking_verbs = true,
-- --         avoid_curses = true,
-- --         terminating_conjunctions = true,
-- --       },
-- --     },
-- --   },
-- -- }
--
-- return {
--   {
--     'dundalek/lazy-lsp.nvim',
--     enabled = false,
--     dependencies = {
--       'neovim/nvim-lspconfig',
--       'Saghen/blink.cmp',
--     },
--     config = function()
--       require('lazy-lsp').setup {
--         excluded_servers = {
--           'ruff_lsp',
--           'ccls',
--           'zk',
--           'ts_ls',
--           'buf_ls',
--           'c3_lsp',
--           'sourcekit',
--         },
--         preferred_servers = {
--           markdown = { 'ltex' },
--           python = { 'basedpyright' },
--           netrw = {},
--         },
--         prefer_local = true,
--         -- Default config passed to all servers to specify on_attach callback and other options.
--         default_config = {
--           flags = {
--             debounce_text_changes = 150,
--           },
--         },
--         -- Override config for specific servers that will passed down to lspconfig setup.
--         -- Note that the default_config will be merged with this specific configuration so you don't need to specify everything twice.
--         configs = {
--           basedpyright = {
--             settings = {
--               basedpyright = {
--                 analysis = {
--                   typeCheckingMode = 'basic',
--                   logLevel = 'error',
--                   -- diagnosticSeverityOverrides = {
--                   --   reportAttributeAccessIssue = 'none',
--                   -- },
--
--                   inlayHints = { variableTypes = true, functionReturnTypes = true },
--                 },
--               },
--               hints = {
--                 enable = true,
--               },
--               codeLens = {
--                 enable = true,
--               },
--             },
--           },
--           lua_ls = {
--             settings = {
--               Lua = {
--                 workspace = {
--                   checkThirdParty = false,
--                 },
--                 hint = {
--                   enable = true,
--                 },
--                 completion = {
--                   displayContext = 1,
--                   callSnippet = 'Both',
--                 },
--               },
--             },
--           },
--           ltex = {
--             settings = {
--               ltex = {
--                 enabled = {
--                   'bibtex',
--                   'gitcommit',
--                   'markdown',
--                   'org',
--                   'tex',
--                   'restructuredtext',
--                   'rsweave',
--                   'latex',
--                   'quarto',
--                   'rmd',
--                   'context',
--                   'html',
--                   'xhtml',
--                 },
--                 workspace = {
--                   checkThirdParty = false,
--                 },
--                 codeLens = {
--                   enable = true,
--                 },
--                 completion = {
--                   callSnippet = 'Replace',
--                 },
--                 dictionary = {
--                   ['en-US'] = words,
--                 },
--               },
--             },
--           },
--         },
--       }
--     end,
--   },
-- }
-- Initially taken from [NTBBloodbath](https://github.com/NTBBloodbath/nvim/blob/main/lua/core/lsp.lua)
-- modified almost 80% by me

-- Diagnostics {{{
vim.diagnostic.config {
  float = {
    focusable = false,
    style = 'minimal',
    border = 'none',
    source = 'always',
    header = '',
    prefix = '',
    suffix = '',
  },
  underline = true,
  update_in_insert = false,

  -- virtual_lines = {
  --   -- Only show virtual line diagnostics for the current cursor line
  --   current_line = true,
  -- },
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
  -- signs = true,
  severity_sort = true,
}
-- }}}

-- Improve LSPs UI {{{
local icons = {
  Class = ' ',
  Color = ' ',
  Constant = ' ',
  Constructor = ' ',
  Enum = ' ',
  EnumMember = ' ',
  Event = ' ',
  Field = ' ',
  File = ' ',
  Folder = ' ',
  Function = '󰊕 ',
  Interface = ' ',
  Keyword = ' ',
  Method = 'ƒ ',
  Module = '󰏗 ',
  Property = ' ',
  Snippet = ' ',
  Struct = ' ',
  Text = ' ',
  Unit = ' ',
  Value = ' ',
  Variable = ' ',
}

local completion_kinds = vim.lsp.protocol.CompletionItemKind
for i, kind in ipairs(completion_kinds) do
  completion_kinds[i] = icons[kind] and icons[kind] .. kind or kind
end
-- }}}

-- Lsp capabilities and on_attach {{{
-- Here we grab default Neovim capabilities and extend them with ones we want on top
local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities.textDocument.foldingRange = {
  dynamicRegistration = true,
  lineFoldingOnly = true,
}

capabilities.textDocument.semanticTokens.multilineTokenSupport = true
capabilities.textDocument.completion.completionItem.snippetSupport = true

vim.lsp.config('*', {
  capabilities = capabilities,
  on_attach = function(client, bufnr)
    local ok, diag = pcall(require, 'rj.extras.workspace-diagnostic')
    if ok then
      diag.populate_workspace_diagnostics(client, bufnr)
    end
  end,
})
-- }}}

-- Disable the default keybinds {{{
for _, bind in ipairs { 'grn', 'gra', 'gri', 'grr' } do
  pcall(vim.keymap.del, 'n', bind)
end
-- }}}

-- Create keybindings, commands, inlay hints and autocommands on LSP attach {{{
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local bufnr = ev.buf
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end
    ---@diagnostic disable-next-line need-check-nil
    if client.server_capabilities.completionProvider then
      vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'
      -- vim.bo[bufnr].omnifunc = "v:lua.MiniCompletion.completefunc_lsp"
    end
    ---@diagnostic disable-next-line need-check-nil
    if client.server_capabilities.definitionProvider then
      vim.bo[bufnr].tagfunc = 'v:lua.vim.lsp.tagfunc'
    end

    -- -- nightly has inbuilt completions, this can replace all completion plugins
    -- if client:supports_method("textDocument/completion", bufnr) then
    --   -- Enable auto-completion
    --   vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
    -- end

    --- Disable semantic tokens
    ---@diagnostic disable-next-line need-check-nil
    client.server_capabilities.semanticTokensProvider = nil

    -- All the keymaps
    -- stylua: ignore start
    local keymap = vim.keymap.set
    local lsp = vim.lsp
    local opts = { silent = true }
    local function opt(desc, others)
      return vim.tbl_extend("force", opts, { desc = desc }, others or {})
    end
    keymap("n", "gd", lsp.buf.definition, opt("Go to definition"))
    keymap("n", "gD", function()
      local ok, diag = pcall(require, "rj.extras.definition")
      if ok then
        diag.get_def()
      end
    end, opt("Get the definition in a float"))
    keymap("n", "gi", function() lsp.buf.implementation({ border = "none" })  end, opt("Go to implementation"))
    -- keymap("n", "gr", lsp.buf.references, opt("Show References"))
    keymap("n", "gl", vim.diagnostic.open_float, opt("Open diagnostic in float"))
    keymap("n", "<C-k>", lsp.buf.signature_help, opts)
    -- disable the default binding first before using a custom one
    pcall(vim.keymap.del, "n", "K", { buffer = ev.buf })
    keymap("n", "K", function() lsp.buf.hover({ border = "none", max_height = 30, max_width = 120 }) end, opt("Toggle hover"))
    keymap("n", "<Leader>lF", vim.cmd.FormatToggle, opt("Toggle AutoFormat"))
    keymap("n", "<Leader>lI", vim.cmd.Mason, opt("Mason"))
    keymap("n", "<Leader>lS", lsp.buf.workspace_symbol, opt("Workspace Symbols"))
    keymap("n", "<Leader>la", lsp.buf.code_action, opt("Code Action"))
    keymap("n", "<Leader>lh", function() lsp.inlay_hint.enable(not lsp.inlay_hint.is_enabled({})) end, opt("Toggle Inlayhints"))
    keymap("n", "<Leader>li", vim.cmd.LspInfo, opt("LspInfo"))
    keymap("n", "<Leader>ll", lsp.codelens.run, opt("Run CodeLens"))
    keymap("n", "<Leader>lr", lsp.buf.rename, opt("Rename"))
    keymap("n", "<Leader>ls", lsp.buf.document_symbol, opt("Doument Symbols"))

    -- diagnostic mappings
    keymap("n", "<Leader>dD", function()
      local ok, diag = pcall(require, "rj.extras.workspace-diagnostic")
      if ok then
        for _, cur_client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
          diag.populate_workspace_diagnostics(cur_client, 0)
        end
        vim.notify("INFO: Diagnostic populated")
      end
    end, opt("Popluate diagnostic for the whole workspace"))
    keymap("n", "<Leader>dn", function() vim.diagnostic.jump({ count = 1, float = true }) end, opt("Next Diagnostic"))
    keymap("n", "<Leader>dp", function() vim.diagnostic.jump({ count =-1, float = true }) end, opt("Prev Diagnostic"))
    keymap("n", "<Leader>dq", vim.diagnostic.setloclist, opt("Set LocList"))
    keymap("n", "<Leader>dv", function()
      vim.diagnostic.config({ virtual_lines = not vim.diagnostic.config().virtual_lines })
    end, opt("Toggle diagnostic virtual_lines"))
    -- stylua: ignore end
  end,
})
-- }}}

-- Servers {{{

-- Lua {{{
vim.lsp.config.lua_ls = {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.git', vim.uv.cwd() },
  settings = {
    Lua = {
      telemetry = {
        enable = false,
      },
    },
  },
}
vim.lsp.enable 'lua_ls'
-- }}}

-- Python {{{
--
-- Define the Pyright config (Neovim 0.10+ built-in LSP style)
-- vim.lsp.config.pyright = {
--   name = 'pyright',
--   filetypes = { 'python' },
--   cmd = { 'pyright-langserver', '--stdio' },
--   settings = {
--     python = {
--       analysis = {
--         autoSearchPaths = true,
--         autoImportCompletions = true,
--         useLibraryCodeForTypes = true,
--         diagnosticMode = 'openFilesOnly', -- or "workspace"
--         typeCheckingMode = 'basic', -- or "off", "strict"
--         inlayHints = {
--           variableTypes = true,
--           callArgumentNames = true,
--           functionReturnTypes = true,
--           genericTypes = false,
--         },
--       },
--       -- Uncomment if you keep venvs here:
--       -- venvPath = vim.fn.expand('~/.virtualenvs'),
--     },
--   },
-- }
--
-- -- Start/attach Pyright when opening Python files
-- vim.api.nvim_create_autocmd('FileType', {
--   pattern = 'python',
--   callback = function()
--     -- Optional: your venv helper
--     local ok, venv = pcall(require, 'rj.extras.venv')
--     if ok then
--       venv.setup()
--     end
--
--     -- Find project root
--     local root = vim.fs.root(0, {
--       'pyproject.toml',
--       'setup.py',
--       'setup.cfg',
--       'requirements.txt',
--       'Pipfile',
--       'pyrightconfig.json',
--       '.git',
--     }) or vim.uv.cwd()
--
--     -- Merge your pyright config with the detected root
--     local cfg = vim.tbl_deep_extend('force', vim.lsp.config.pyright or {}, { root_dir = root })
--
--     local client_id = vim.lsp.start(cfg) -- returns client id (number)
--     if client_id then
--       vim.lsp.buf_attach_client(0, client_id)
--     end
--   end,
-- })
-- }}}

-- C/C++ {{{
vim.lsp.config.clangd = {
  cmd = {
    'clangd',
    '-j=' .. 2,
    '--background-index',
    '--clang-tidy',
    '--inlay-hints',
    '--fallback-style=llvm',
    '--all-scopes-completion',
    '--completion-style=detailed',
    '--header-insertion=iwyu',
    '--header-insertion-decorators',
    '--pch-storage=memory',
  },
  filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
  root_markers = {
    'CMakeLists.txt',
    '.clangd',
    '.clang-tidy',
    '.clang-format',
    'compile_commands.json',
    'compile_flags.txt',
    'configure.ac',
    '.git',
    vim.uv.cwd(),
  },
}
vim.lsp.enable 'clangd'
-- }}}

-- Typst {{{
vim.lsp.config.tinymist = {
  cmd = { 'tinymist' },
  filetypes = { 'typst' },
  root_markers = { '.git', vim.uv.cwd() },
}

vim.lsp.enable 'tinymist'
-- }}}

-- Bash {{{
vim.lsp.config.bashls = {
  cmd = { 'bash-language-server', 'start' },
  filetypes = { 'bash', 'sh', 'zsh' },
  root_markers = { '.git', vim.uv.cwd() },
  settings = {
    bashIde = {
      globPattern = vim.env.GLOB_PATTERN or '*@(.sh|.inc|.bash|.command)',
    },
  },
}
vim.lsp.enable 'bashls'
-- }}}

-- Web-dev {{{
-- TSServer {{{
vim.lsp.config.ts_ls = {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'javascript.jsx', 'typescript', 'typescriptreact', 'typescript.tsx' },
  root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' },

  init_options = {
    hostInfo = 'neovim',
  },
}
-- }}}

-- CSSls {{{
vim.lsp.config.cssls = {
  cmd = { 'vscode-css-language-server', '--stdio' },
  filetypes = { 'css', 'scss' },
  root_markers = { 'package.json', '.git' },
  init_options = {
    provideFormatter = true,
  },
}
-- }}}

-- TailwindCss {{{
vim.lsp.config.tailwindcssls = {
  cmd = { 'tailwindcss-language-server', '--stdio' },
  filetypes = {
    'ejs',
    'html',
    'css',
    'scss',
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
  },
  root_markers = {
    'tailwind.config.js',
    'tailwind.config.cjs',
    'tailwind.config.mjs',
    'tailwind.config.ts',
    'postcss.config.js',
    'postcss.config.cjs',
    'postcss.config.mjs',
    'postcss.config.ts',
    'package.json',
    'node_modules',
  },
  settings = {
    tailwindCSS = {
      classAttributes = { 'class', 'className', 'class:list', 'classList', 'ngClass' },
      includeLanguages = {
        eelixir = 'html-eex',
        eruby = 'erb',
        htmlangular = 'html',
        templ = 'html',
      },
      lint = {
        cssConflict = 'warning',
        invalidApply = 'error',
        invalidConfigPath = 'error',
        invalidScreen = 'error',
        invalidTailwindDirective = 'error',
        invalidVariant = 'error',
        recommendedVariantOrder = 'warning',
      },
      validate = true,
    },
  },
}
-- }}}

-- HTML {{{
vim.lsp.config.htmlls = {
  cmd = { 'vscode-html-language-server', '--stdio' },
  filetypes = { 'html' },
  root_markers = { 'package.json', '.git' },

  init_options = {
    configurationSection = { 'html', 'css', 'javascript' },
    embeddedLanguages = {
      css = true,
      javascript = true,
    },
    provideFormatter = true,
  },
}
-- }}}

vim.lsp.enable { 'ts_ls', 'cssls', 'tailwindcssls', 'htmlls' }

-- }}}

-- }}}

-- Start, Stop, Restart, Log commands {{{
vim.api.nvim_create_user_command('LspStart', function()
  vim.cmd.e()
end, { desc = 'Starts LSP clients in the current buffer' })

vim.api.nvim_create_user_command('LspStop', function(opts)
  for _, client in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
    if opts.args == '' or opts.args == client.name then
      client:stop(true)
      vim.notify(client.name .. ': stopped')
    end
  end
end, {
  desc = 'Stop all LSP clients or a specific client attached to the current buffer.',
  nargs = '?',
  complete = function(_, _, _)
    local clients = vim.lsp.get_clients { bufnr = 0 }
    local client_names = {}
    for _, client in ipairs(clients) do
      table.insert(client_names, client.name)
    end
    return client_names
  end,
})

vim.api.nvim_create_user_command('LspRestart', function()
  local detach_clients = {}
  for _, client in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
    client:stop(true)
    if vim.tbl_count(client.attached_buffers) > 0 then
      detach_clients[client.name] = { client, vim.lsp.get_buffers_by_client_id(client.id) }
    end
  end
  local timer = vim.uv.new_timer()
  if not timer then
    return vim.notify 'Servers are stopped but havent been restarted'
  end
  timer:start(
    100,
    50,
    vim.schedule_wrap(function()
      for name, client in pairs(detach_clients) do
        local client_id = vim.lsp.start(client[1].config, { attach = false })
        if client_id then
          for _, buf in ipairs(client[2]) do
            vim.lsp.buf_attach_client(buf, client_id)
          end
          vim.notify(name .. ': restarted')
        end
        detach_clients[name] = nil
      end
      if next(detach_clients) == nil and not timer:is_closing() then
        timer:close()
      end
    end)
  )
end, {
  desc = 'Restart all the language client(s) attached to the current buffer',
})

vim.api.nvim_create_user_command('LspLog', function()
  vim.cmd.vsplit(vim.lsp.log.get_filename())
end, {
  desc = 'Get all the lsp logs',
})

vim.api.nvim_create_user_command('LspInfo', function()
  vim.cmd 'silent checkhealth vim.lsp'
end, {
  desc = 'Get all the information about all LSP attached',
})
-- }}}

vim.lsp.config.basedpyright = {
  cmd = { 'basedpyright-langserver', '--stdio' },
  filetypes = { 'python' },
  -- root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', 'pyrightconfig.json', '.git' },
  settings = {
    basedpyright = {
      analysis = {
        autoSearchPaths = true,
        autoImportCompletions = true,
        useLibraryCodeForTypes = true,
        diagnosticMode = 'openFilesOnly', -- or "workspace"
        typeCheckingMode = 'basic', -- "off" | "basic" | "standard" | "strict"
        inlayHints = {
          variableTypes = true,
          callArgumentNames = true,
          functionReturnTypes = true,
          genericTypes = false,
        },
      },
    },
  },
}
vim.lsp.enable 'basedpyright'
-- vim: fdm=marker:fdl=0
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
}
