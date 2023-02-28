local map = require('core.keymap')
local cmd = map.cmd

map.n({
  ['<C-s>'] = cmd('write'),
  ['<C-x>k'] = cmd('bdelete'),
  ['<C-n>'] = cmd('bn'),
  ['<C-p>'] = cmd('bp'),
  ['<C-q>'] = cmd('qa!'),
  ['<C-e>'] = cmd('quit'),
  [']b'] = cmd('bn'),
  ['[b'] = cmd('bp'),
  --window
  ['<C-h>'] = '<C-w>h',
  ['<C-l>'] = '<C-w>l',
  ['<C-j>'] = '<C-w>j',
  ['<C-k>'] = '<C-w>k',
  ['<A-[>'] = cmd('vertical resize -5'),
  ['<A-]>'] = cmd('vertical resize +5'),
  ['<S-Up>'] = cmd('move . -2'),
  ['<S-Down>'] = cmd('move . +1'),
})

map.i({
  ['<C-b>'] = '<ESC>diwa',
  ['<C-w>'] = '<ESC>dwa',
  ['<C-h>'] = '<Bs>',
  ['<C-d>'] = '<Del>',
  ['<C-u>'] = '<C-G>u<C-u>',
  ['<C-a>'] = '<Esc>^i',
  ['<C-j>'] = '<Esc>o',
  ['<C-k>'] = '<Esc>O',
  ['<C-s>'] = '<ESC>:w<CR>a',
})

map.i('<c-e>', function()
  return vim.fn.pumvisible() == 1 and '<C-e>' or '<End>'
end, { expr = true })

map.c({
  ['<C-b>'] = '<Left>',
  ['<C-f>'] = '<Right>',
  ['<C-a>'] = '<Home>',
  ['<C-e>'] = '<End>',
  ['<C-d>'] = '<Del>',
  ['<C-h>'] = '<BS>',
})

map.t('<Esc>', [[<C-\><C-n>]])
