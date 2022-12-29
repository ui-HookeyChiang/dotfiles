local bind = require('keymap.bind')
local map_cr = bind.map_cr
local map_cu = bind.map_cu
local map_cmd = bind.map_cmd

-- default map
local def_map = {
    -- Vim map
    ["n|<C-x>k"]     = map_cr('bdelete'):with_noremap():with_silent(),
    ["n|Y"]          = map_cmd('y$'),
    ["n|]w"]         = map_cu('WhitespaceNext'):with_noremap(),
    ["n|[w"]         = map_cu('WhitespacePrev'):with_noremap(),
    ["n|]b"]         = map_cu('bp'):with_noremap(),
    ["n|[b"]         = map_cu('bn'):with_noremap(),
    ["n|<Leader>tw"] = map_cu('TrimTrailingWhitespace'):with_noremap(),
    ["n|<C-h>"]      = map_cmd('<C-w>h'):with_noremap(),
    ["n|<C-l>"]      = map_cmd('<C-w>l'):with_noremap(),
    ["n|<C-j>"]      = map_cmd('<C-w>j'):with_noremap(),
    ["n|<C-k>"]      = map_cmd('<C-w>k'):with_noremap(),
    ["n|<A-[>"]      = map_cr('vertical resize -5'):with_silent(),
    ["n|<A-]>"]      = map_cr('vertical resize +5'):with_silent(),
    ["n|<Leader>ss"] = map_cu('SessionSave'):with_noremap(),
    ["n|<Leader>sl"] = map_cu('SessionLoad'):with_noremap(),
    ["n|<C-s>"]      = map_cu('write'):with_noremap(),
    ["n|<C-e>"]      = map_cmd(':q!<CR>'),
    ["n|<S-Left>"]   = map_cmd(':tabprevious<CR>'):with_noremap(),
    ["n|<S-Right>"]  = map_cmd(':tabnext<CR>'):with_noremap(),
    ["n|<S-Up>"]     = map_cmd(':m .-2<CR>'):with_noremap(),
    ["n|<S-Down>"]   = map_cmd(':m .+1<CR>'):with_noremap(),
    ["n|<S-Home>"]   = map_cmd(':tabm -1<CR>'):with_noremap(),
    ["n|<S-End>"]    = map_cmd(':tabm +1<CR>'):with_noremap(),
    ["n|<F10>"]      = map_cmd(':set nu!<CR>'):with_noremap(),
  -- Insert
    ["i|<C-w>"]      = map_cmd('<C-[>diwa'):with_noremap(),
    ["i|<C-h>"]      = map_cmd('<BS>'):with_noremap(),
    ["i|<C-d>"]      = map_cmd('<Del>'):with_noremap(),
    ["i|<C-u>"]      = map_cmd('<C-G>u<C-U>'):with_noremap(),
    ["i|<C-b>"]      = map_cmd('<Left>'):with_noremap(),
    ["i|<C-f>"]      = map_cmd('<Right>'):with_noremap(),
    ["i|<C-a>"]      = map_cmd('<ESC>^i'):with_noremap(),
    ["i|<C-j>"]      = map_cmd('<Esc>o'):with_noremap(),
    ["i|<C-k>"]      = map_cmd('<Esc>O'):with_noremap(),
    ["i|<C-s>"]      = map_cmd('<Esc>:w<CR>'),
    ["i|<C-e>"]      = map_cmd('<Esc>:q!<CR>'),
    --["i|<S-e>"]      = map_cmd([[pumvisible() ? "\<C-e>" : "\<End>"]]):with_noremap():with_expr(),
    ["i|<S-Left>"]   = map_cmd('<ESC>:tabprevious<CR>'):with_noremap(),
    ["i|<S-Right>"]  = map_cmd('<ESC>:tabnext<CR>'):with_noremap(),
    ["i|<S-Up>"]     = map_cmd('<ESC>:m .-2<CR>'):with_noremap(),
    ["i|<S-Down>"]   = map_cmd('<ESC>:m .+1<CR>'):with_noremap(),
  -- command line
    ["c|<C-b>"]      = map_cmd('<Left>'):with_noremap(),
    ["c|<C-f>"]      = map_cmd('<Right>'):with_noremap(),
    ["c|<C-a>"]      = map_cmd('<Home>'):with_noremap(),
    ["c|<C-e>"]      = map_cmd('<End>'):with_noremap(),
    ["c|<C-d>"]      = map_cmd('<Del>'):with_noremap(),
    ["c|<C-h>"]      = map_cmd('<BS>'):with_noremap(),
    ["c|<C-t>"]      = map_cmd([[<C-R>=expand("%:p:h") . "/" <CR>]]):with_noremap(),
}

bind.nvim_load_mapping(def_map)
