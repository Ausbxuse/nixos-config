return {
  {
    'mfussenegger/nvim-dap',
    event = 'VeryLazy',
    config = function()
      local dap = require 'dap'
      local repl = require 'dap.repl'
      local widgets = require 'dap.ui.widgets'

      vim.fn.sign_define('DapBreakpoint', {
        text = '●',
        texthl = 'Debug',
      })
      vim.fn.sign_define('DapStopped', {
        text = '',
        texthl = 'PreProc',
      })

      dap.adapters.python = function(callback, config)
        local connect = config.connect or {}
        callback {
          type = 'server',
          host = connect.host or '127.0.0.1',
          port = connect.port or 5678,
          options = {
            source_filetype = 'python',
          },
        }
      end

      dap.configurations.python = {
        {
          type = 'python',
          request = 'attach',
          name = 'Attach debugpy :5678',
          connect = {
            host = '127.0.0.1',
            port = 5678,
          },
          justMyCode = false,
        },
      }

      dap.adapters.gdb = {
        type = 'executable',
        command = 'gdb',
        args = { '-q', '--interpreter=dap', '--eval-command', 'set print pretty on' },
      }

      local function pick_executable()
        return vim.fn.input('Executable: ', vim.fn.getcwd() .. '/', 'file')
      end

      dap.configurations.c = {
        {
          name = 'Launch executable',
          type = 'gdb',
          request = 'launch',
          program = pick_executable,
          cwd = '${workspaceFolder}',
          stopAtBeginningOfMainSubprogram = false,
        },
      }
      dap.configurations.cpp = dap.configurations.c

      vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'DAP breakpoint' })
      vim.keymap.set('n', '<leader>dB', function()
        dap.set_breakpoint(vim.fn.input 'Condition: ')
      end, { desc = 'DAP conditional breakpoint' })
      vim.keymap.set('n', '<leader>dc', dap.continue, { desc = 'DAP continue/attach' })
      vim.keymap.set('n', '<leader>dd', dap.terminate, { desc = 'DAP terminate' })
      vim.keymap.set('n', '<leader>di', dap.step_into, { desc = 'DAP step into' })
      vim.keymap.set('n', '<leader>dn', dap.step_over, { desc = 'DAP step over' })
      vim.keymap.set('n', '<leader>do', dap.step_out, { desc = 'DAP step out' })
      vim.keymap.set('n', '<leader>dk', widgets.hover, { desc = 'DAP hover' })
      vim.keymap.set('n', '<leader>dr', function()
        repl.toggle({}, 'belowright split')
      end, { desc = 'DAP REPL' })
    end,
  },

  {
    'rcarriga/nvim-dap-ui',
    event = 'VeryLazy',
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    config = function()
      local dapui = require 'dapui'

      dapui.setup {
        controls = {
          enabled = false,
        },
        floating = {
          border = 'noborder',
          mappings = {
            close = { 'q', '<Esc>' },
          },
        },
        layouts = {
          {
            elements = {
              { id = 'scopes', size = 0.50 },
              { id = 'stacks', size = 0.25 },
              { id = 'breakpoints', size = 0.25 },
            },
            position = 'right',
            size = 45,
          },
          {
            elements = {
              { id = 'repl', size = 0.5 },
              { id = 'console', size = 0.5 },
            },
            position = 'bottom',
            size = 10,
          },
        },
        render = {
          indent = 1,
          max_value_lines = 100,
        },
      }

      vim.keymap.set('n', '<leader>du', dapui.toggle, { desc = 'DAP UI' })
    end,
  },
}
