local package = require('core.pack').package
local conf = require('modules.completion.config')

local enable_lsp_filetype = {
  'go',
  'lua',
  'sh',
  'rust',
  'c',
  'cpp',
  'zig',
  'typescript',
  'typescriptreact',
  'json',
  'python',
 -- 'proto',
  'markdown',
}

package({
  'neovim/nvim-lspconfig',
  ft = enable_lsp_filetype,
  config = conf.nvim_lsp,
  dependencies = {
    {'glepnir/lspsaga.nvim', event={'BufRead', 'BufReadPost'}, config = conf.lspsaga },
    {'williamboman/mason-lspconfig.nvim'},
    {'williamboman/mason.nvim'},
    {'jose-elias-alvarez/null-ls.nvim'},
    {'jayp0521/mason-null-ls.nvim'},
  },
})

package({
  'hrsh7th/nvim-cmp',
  event = 'InsertEnter',
  config = conf.nvim_cmp,
  dependencies = {
    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-buffer',
    'saadparwaiz1/cmp_luasnip',
  },
})

package({
    'L3MON4D3/LuaSnip',
    event = 'InsertCharPre',
    config = conf.lua_snip,
    dependencies = {'saadparwaiz1/cmp_luasnip'},
})

package({ 'windwp/nvim-autopairs', event = 'InsertEnter', config = conf.auto_pairs })
