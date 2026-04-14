return { -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>fm',
      function()
        require('conform').format { async = true, lsp_format = 'fallback' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  init = function()
    vim.api.nvim_create_user_command('ConformDisable', function(args)
      if args.bang then
        vim.b.disable_autoformat = true
      else
        vim.g.disable_autoformat = true
      end
    end, { bang = true, desc = 'Disable format-on-save (! = buffer only)' })
    vim.api.nvim_create_user_command('ConformEnable', function(args)
      if args.bang then
        vim.b.disable_autoformat = false
      else
        vim.g.disable_autoformat = false
      end
    end, { bang = true, desc = 'Enable format-on-save (! = buffer only)' })
  end,
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
        return
      end
      return {
        timeout_ms = 500,
        lsp_fallback = false,
      }
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      nix = { 'alejandra' },
      python = { 'isort', 'black' },
      markdown = { 'prettier' },
      javascript = { 'prettier' },
      javascriptreact = { 'prettier' },
    },
  },
  config = function(_, opts)
    require('conform').setup(opts)
  end,
}
