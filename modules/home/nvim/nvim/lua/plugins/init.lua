local spec_modules = {
  require 'plugins.cmp',
  require 'plugins.dap',
  require 'plugins.editor',
  require 'plugins.extra',
  require 'plugins.formatting',
  require 'plugins.fzf',
  require 'plugins.git',
  require 'plugins.lsp',
  require 'plugins.ui',
}

require('config.pack').setup(spec_modules)
