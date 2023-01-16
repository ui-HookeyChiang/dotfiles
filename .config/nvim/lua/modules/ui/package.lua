local package = require('core.pack').package
local conf = require('modules.ui.config')

package({ 'folke/tokyonight.nvim', config = conf.tokyonight })

--package({ 'glepnir/zephyr-nvim', config = conf.zephyr })

package({ 'glepnir/dashboard-nvim', event = 'VimEnter', config = conf.dashboard })

package({
  'glepnir/galaxyline.nvim',
  config = conf.galaxyline,
  dependencies = { 'nvim-tree/nvim-web-devicons' },
})

local enable_indent_filetype = {
  'go',
  'lua',
  'sh',
  'rust',
  'cpp',
  'typescript',
  'typescriptreact',
  'javascript',
  'json',
  'python',
}

package({
  'lukas-reineke/indent-blankline.nvim',
  ft = enable_indent_filetype,
  config = conf.indent_blankline,
})

package({
  'lewis6991/gitsigns.nvim',
  event = { 'BufRead', 'BufNewFile' },
  config = conf.gitsigns,
})
