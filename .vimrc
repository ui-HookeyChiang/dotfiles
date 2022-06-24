set nocompatible              " be iMproved

call plug#begin()

" custom plugins
Plug 'fatih/vim-go'
Plug 'majutsushi/tagbar'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'tpope/vim-fugitive'
"""""""""""""""""""""""
"Nerdtree File Manager"
"""""""""""""""""""""""
Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'scrooloose/nerdcommenter'
Plug 'jistr/vim-nerdtree-tabs'
" 可以在導航目錄中看到 git 版本資訊
Plug 'Xuyuanp/nerdtree-git-plugin'

Plug 'mbbill/undotree'
Plug 'Lokaltog/vim-easymotion'
"" Great tool for auto-completion of variables and functions
Plug 'Valloric/YouCompleteMe'
"" Good Auto Fill Tool use F2 to trigger
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
"" This plug-in provides automatic closing of quotes, parenthesis, brackets, etc.
Plug 'Raimondi/delimitMate'
"" C and other languages' formatting
Plug 'Chiel92/vim-autoformat'
"" These two are for mark-down
"Plug 'godlygeek/tabular'
"Plug 'plasticboy/vim-markdown'
Plug 'tomasr/molokai'
"" OSC52: Ctrl+c copy to clipboard in vim
Plug 'fcpg/vim-osc52'
"" Fuzzy Search
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' } 
Plug 'junegunn/fzf.vim'
"" all of your Plugins must be added before the following line
call plug#end()            " required

" general customizations
syntax on

"" Auto save on make with
set autowrite
set ts=4
set sw=4
set number
set cursorline
set scrolloff=5
set encoding=utf-8
"" Easier to delete space(tab)
set smarttab
set hlsearch
"" do not history when leavy buffer
set hidden
set complete-=i
set showmode
set shiftround
set ttimeout
set ttimeoutlen=50
set incsearch
set ignorecase
set laststatus=2
set ruler
set showcmd
set wildmenu
set noswapfile
set fileformats=unix,dos,mac

set cursorline
set completeopt=menuone,longest,preview
set virtualedit=onemore

set completeopt-=preview

set background=dark
set backspace=indent,eol,start
highlight clear

if exists("syntax_on")
  syntax reset
endif
set t_Co=256
set term=xterm-256color

"" explicitly show trailing spaces, tab, eol
set list!
set listchars=tab:>\ ,trail:·

" Markdown
"let g:vim_markdown_folding_disabled=1
"let g:vim_markdown_math=1

" fzf Fuzzy find recent global files/local files/contents
command! FZFMru call fzf#run({
	\  'source':  v:oldfiles,
	\  'sink':    'e',
	\  'options': '-m -x +s',
	\  'down':    '67%'})
command! -nargs=* AG call fzf#run({
	\ 'source':  printf('ag --nogroup --column --color "%s"',
	\                   escape(empty(<q-args>) ? '^(?=.)' : <q-args>, '"\')),
	\ 'sink*':    function('<sid>ag_handler'),
	\ 'options': '--ansi --expect=ctrl-t,ctrl-v,ctrl-x --delimiter : --nth 4.. '.
	\            '--multi --bind=ctrl-a:select-all,ctrl-d:deselect-all '.
	\            '--color hl:68,hl+:110',
	\ 'down':    '67%'
	\ }, 
	\ fzf#vim#with_preview({'dir': function('<sid>GetProjectRoot')}, 'right:50%'))

"" Gets the root of the Git repo or submodule, relative to the current buffer, or home dir
function! s:GetProjectRoot()
	let project_root = system('git -C ' . shellescape(expand('%:p:h')) . ' rev-parse --show-toplevel 2> /dev/null')[:-2]
	if strlen(project_root) > 0
		return project_root
	else
		return system('echo $HOME')
	endif
endfunction

function! s:ag_to_qf(line)
  let parts = split(a:line, ':')
  return {'filename': parts[0], 'lnum': parts[1], 'col': parts[2],
        \ 'text': join(parts[3:], ':')}
endfunction

function! s:ag_handler(lines)
  if len(a:lines) < 2 | return | endif

  let cmd = get({'ctrl-x': 'split',
               \ 'ctrl-v': 'vertical split',
               \ 'ctrl-t': 'tabe'}, a:lines[0], 'e')
  let list = map(a:lines[1:], 's:ag_to_qf(v:val)')

  let first = list[0]
  execute cmd escape(first.filename, ' %#\')
  execute first.lnum
  execute 'normal!' first.col.'|zz'

  if len(list) > 1
    call setqflist(list)
    copen
    wincmd p
  endif
endfunction

"" fzf settings
"" This is the default extra key bindings
let g:fzf_action = {
            \ 'ctrl-t': 'tab split',
            \ 'ctrl-x': 'split',
            \ 'ctrl-v': 'vsplit' }

"" Default fzf layout
"" - down / up / left / right
let g:fzf_layout = { 'down': '67%' }

"" Customize fzf colors to match your color scheme
let g:fzf_colors =
            \ { 'fg':    ['fg', 'Normal'],
            \ 'bg':      ['bg', 'Normal'],
            \ 'hl':      ['fg', 'Comment'],
            \ 'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
            \ 'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
            \ 'hl+':     ['fg', 'Statement'],
            \ 'info':    ['fg', 'PreProc'],
            \ 'prompt':  ['fg', 'Conditional'],
            \ 'pointer': ['fg', 'Exception'],
            \ 'marker':  ['fg', 'Keyword'],
            \ 'spinner': ['fg', 'Label'],
            \ 'header':  ['fg', 'Comment'] }

"" Enable per-command history.
"" CTRL-N and CTRL-P will be automatically bound to next-history and
"" previous-history instead of down and up. If you don't like the change,
"" explicitly bind the keys to down and up in your $FZF_DEFAULT_OPTS.
let g:fzf_history_dir = '~/.local/share/fzf-history'

" vim-go
"" cheatsheet: https://gist.github.com/krlvi/d22bdcb66566261ea8e8da36f796fa0a
"" disable open browser after posting snippet
let g:go_play_open_browser = 0
"" enable goimports
let g:go_fmt_command = "goimports"
"" enable additional highlighting
let g:go_highlight_functions = 1
"" Format on save
let g:go_fmt_autosave = 1
"" Disable gofmt parse errors
let g:go_fmt_fail_silently = 1
let g:go_highlight_methods = 1
let g:go_highlight_structs = 1
let g:go_gopls_enabled = 1
let g:go_gopls_options = ['-remote=auto']
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
let g:go_referrers_mode = 'gopls'
let g:go_metalinter_enabled = ['vet', 'golint', 'errcheck', 'deadcode']
let g:go_metalinter_autosave = 1
let g:go_metalinter_autosave_enabled = ['vet', 'golint']

"""""""""""""""""""""""""
"for airline status bar"
""""""""""""""""""""""""
"refer to https://github.com/vim-airline/vim-airline/wiki/Screenshots for
"colorschemes Screenshots
let g:airline#extensions#fugitiveline#enabled = 0
let g:bufferline_echo = 0
let g:airline#extensions#tabline#enabled = 1
""let g:airline_theme = 'powerlineish'
""let g:airline_powerline_fonts = 1
"" This can prevent the bug when only one tab left
let g:airline#extensions#tabline#show_buffers = 0
"" Show tab number by its sequence
let g:airline#extensions#tabline#tab_nr_type = 1
let g:airline#extensions#tabline#fnamemod = ':t'

let g:airline#parts#ffenc#skip_expected_string='utf-8[unix]'
let g:airline_section_warning = ''
let g:airline_section_error = ''
let g:airline_section_z = '%p%% %l/%L:%v'

"""""""""""""""""
"You Complete Me"
"""""""""""""""""
let g:ycm_python_binary_path = '/usr/bin/python3'
let g:ycm_gopls_binary_path = "~/go/bin/gopls"
let g:ycm_gopls_args = ['-remote=auto']
let g:ycm_min_num_identifier_candidate_chars = 2
let g:ycm_completion_confirm_key = '<Right>'
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_autoclose_preview_window_after_insertion = 1
"let g:ycm_global_ycm_extra_conf = '~/.ycm_extra_conf.py'
let g:ycm_confirm_extra_conf = 0  " 不提示是否载入本地ycm_extra_conf文件

"" 语法关键字、注释、字符串补全
let g:ycm_seed_identifiers_with_syntax = 1
let g:ycm_complete_in_comments = 1
let g:ycm_complete_in_strings = 1
"" 从注释、字符串、tag文件中收集用于补全信息
let g:ycm_collect_identifiers_from_comments_and_strings = 1
let g:ycm_collect_identifiers_from_tags_files = 1

"" 禁止快捷键触发补全
let g:ycm_key_invoke_completion = '<c-space>'  " 主动补全(默认<c-space>)

"" 输入2个字符就触发补全
let g:ycm_semantic_triggers = {
            \ 'c,cpp,python,java,go,erlang,perl,py': ['re!\w{2}', '_'],
            \ 'cs,lua,javascript': ['re!\w{2}', '_'],
            \ }
let g:ycm_show_diagnostics_ui = 0  " 禁用YCM自带语法检查(使用ale)

"" 防止YCM和Ultisnips的TAB键冲突，禁止YCM的TAB
let g:ycm_key_list_select_completion = ['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion = ['<C-p>', '<Up>']

" Ultisnip
let g:did_UltiSnips_vim_after = 1
let g:UltiSnipsEditSplit="vertical"
let g:UltiSnipsExpandTrigger = "<NOP>"
let g:UltiSnipsJumpForwardTrigger = "<TAB>"
let g:UltiSnipsJumpBackwardTrigger = "<C-b>"
function ExpandSnippet()
    call UltiSnips#ExpandSnippet()
    if g:ulti_expand_res
        return ""
    else
        return "\<CR>"
    endif
endfunction
inoremap <expr> <CR> pumvisible() ? "<C-R>=ExpandSnippet()<CR>" : "\<CR>"

" tagbar
let g:tagbar_autofocus=1
let g:tagbar_foldlevel=2
let g:tagbar_type_go = {
    \ 'ctagstype' : 'go',
    \ 'kinds' : [
        \ 'p:package',
        \ 'i:imports:1',
        \ 'c:constants',
        \ 'v:variables',
        \ 't:types',
        \ 'n:interfaces',
        \ 'w:fields',
        \ 'e:embedded',
        \ 'm:methods',
        \ 'r:constructor',
        \ 'f:functions'
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 't' : 'ctype',
        \ 'n' : 'ntype'
    \ },
    \ 'scope2kind' : {
        \ 'ctype' : 't',
        \ 'ntype' : 'n'
    \ },
    \ 'ctagsbin'  : 'gotags',
    \ 'ctagsargs' : '-sort -silent'
\ }

" EasyMotion
let g:EasyMotion_do_mapping = 0

" vim-autoformat
let g:autoformat_autoindent = 0 
let g:autoformat_retab = 0 
let g:autoformat_remove_trailing_spaces = 0
let g:formatterpath = ['gofmt', 'clang-format', 'prettier']
nmap == :Autoformat<CR>
autocmd BufEnter *.go* exe 'vmap = :Autoformat<CR>'
autocmd BufEnter *.c* exe 'vmap = :Autoformat<CR>'
autocmd BufEnter *.json* exe 'vmap = :Autoformat<CR>'

" Open markdown files with Chrome.
autocmd BufEnter *.md exe 'noremap <F4> :!google-chrome-stable %:p<CR>'

"""""""""""
"NERDTree "
"""""""""""
" Start NERDTree and leave the cursor in it.
" autocmd VimEnter * NERDTree

"start nerdtree and put cursor in empty buffer or file
autocmd VimEnter * NERDTree | wincmd p

" Start NERDTree when Vim is started without file arguments. 
" below 2 lines were commented for startify to work
"" autocmd StdinReadPre * let s:std_in=1
"" autocmd VimEnter * if argc() == 0 && !exists('s:std_in') | NERDTree | endif

" If another buffer tries to replace NERDTree, put it in the other window, and bring back NERDTree.
autocmd BufEnter * if bufname('#') =~ 'NERD_tree_\d\+' && bufname('%') !~ 'NERD_tree_\d\+' && winnr('$') > 1 |
    \ let buf=bufnr() | buffer# | execute "normal! \<C-W>w" | execute 'buffer'.buf | endif
" Exit Vim if NERDTree is the only window remaining in the only tab.
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

let g:NERDTreeWinSize=20

"disable 80 extentions of nerdtree for less lag
let g:NERDTreeLimitedSyntax = 1

" Create default mappings
let g:NERDCreateDefaultMappings = 1

" Add spaces after comment delimiters by default
let g:NERDSpaceDelims = 1

" Use compact syntax for prettified multi-line comments
let g:NERDCompactSexyComs = 1

" Align line-wise comment delimiters flush left instead of following code indentation
let g:NERDDefaultAlign = 'left'

" Set a language to use its alternate delimiters by default
let g:NERDAltDelims_java = 1

" Add your own custom formats or override the defaults
let g:NERDCustomDelimiters = { 'c': { 'left': '/**','right': '*/' } }

" Allow commenting and inverting empty lines (useful when commenting a region)
let g:NERDCommentEmptyLines = 1

" Enable trimming of trailing whitespace when uncommenting
let g:NERDTrimTrailingWhitespace = 1

" Enable NERDCommenterToggle to check all selected lines is commented or not 
let g:NERDToggleCheckAllLines = 1

"""""""""""""""""""""""""""""""""
" NERDTree Functions and colors "
"""""""""""""""""""""""""""""""""
let g:NERDTreeDirArrowExpandable = ''
let g:NERDTreeDirArrowCollapsible = ''
let g:NERDTreeHighlightFolders = 1 " enables folder icon highlighting using exact match
let g:NERDTreeHighlightFoldersFullName = 1 " highlights the folder name
" you can add these colors to your .vimrc to help customizing
let s:brown = "905532"
let s:aqua =  "3AFFDB"
let s:blue = "689FB6"
let s:darkBlue = "44788E"
let s:purple = "834F79"
let s:lightPurple = "834F79"
let s:red = "AE403F"
let s:beige = "F5C06F"
let s:yellow = "F09F17"
let s:orange = "D4843E"
let s:darkOrange = "F16529"
let s:pink = "CB6F6F"
let s:salmon = "EE6E73"
let s:green = "8FAA54"
let s:lightGreen = "31B53E"
let s:white = "FFFFFF"
let s:rspec_red = 'FE405F'
let s:git_orange = 'F54D27'

let g:NERDTreeExtensionHighlightColor = {} " this line is needed to avoid error
let g:NERDTreeExtensionHighlightColor['css'] = s:blue " sets the color of css files to blue

let g:NERDTreeExactMatchHighlightColor = {} " this line is needed to avoid error
let g:NERDTreeExactMatchHighlightColor['.gitignore'] = s:git_orange " sets the color for .gitignore files

let g:NERDTreePatternMatchHighlightColor = {} " this line is needed to avoid error
let g:NERDTreePatternMatchHighlightColor['.*_spec\.rb$'] = s:rspec_red " sets the color for files ending with _spec.rb

let g:WebDevIconsDefaultFolderSymbolColor = s:beige " sets the color for folders that did not match any rule
let g:WebDevIconsDefaultFileSymbolColor = s:blue " sets the color for files that did not match any rule

"""""""""""""""""""
" Custom Mappings "
"""""""""""""""""""
nmap <F5> :UndotreeToggle<CR>
nmap <F7> :NERDTreeTabsToggle<CR>
nmap <F8> :TagbarToggle<CR>

" Show number of line
nmap <F10> :set nu!<CR>

" Switch btw tabs
nmap <silent> <S-home> :tabprevious<CR>
nmap <silent> <S-end> :tabnext<CR>
imap <silent> <S-home> <Esc>:tabprevious<CR>i
imap <silent> <S-end> <Esc>:tabnext<CR>i
nmap <silent> <S-Left> :tabprevious<CR>
nmap <silent> <S-Right> :tabnext<CR>
imap <silent> <S-Left> <Esc>:tabprevious<CR>i
imap <silent> <S-Right> <Esc>:tabnext<CR>i

" Move line up down
nmap <S-Down> :m .+1<CR>==
nnoremap <S-Up> :m .-2<CR>==
imap <S-Down> <Esc>:m .+1<CR>==gi
inoremap <S-Up> <Esc>:m .-2<CR>==gi
vmap <S-Down> :m '>+1<CR>gv=gv
vnoremap <S-Up> :m '<-2<CR>gv=gv

" Switch btw splitted windows
nmap <silent> <S-j> :wincmd h<CR>
nmap <silent> <S-l> :wincmd l<CR>
nmap <silent> <S-i> :wincmd k<CR>
nmap <silent> <S-k> :wincmd j<CR>

" Exit
noremap  <S-E> :q!<CR>
vnoremap <S-E> <C-C>:q!<CR>

" Save
noremap  <S-S> :update<CR>
vnoremap <S-S> <C-C>:update<CR>

" ???
inoremap <C-U> <C-G>u<C-U>i

" Ctrl+J跳转至定义、声明或文件
let mapleader = 'y'
nnoremap <leader>g :YcmCompleter GoToDefinitionElseDeclaration<CR>
nnoremap <leader>c :YcmCompleter GoToReferences<CR>
nnoremap <leader>s :YcmCompleter GoToSymbol <C-R>=expand("<cword>")<CR><CR>
nnoremap <leader>r :YcmCompleter RefactorRename<space>

" OSC52: Ctrl+c copy to clipboard in vim
vmap <C-c> y:Oscyank<CR>

vnoremap $ $h

autocmd FileType make set noexpandtab
" jump between errors in quickfix list
let mapleader = 'c'
map <leader>n :cnext<CR>
map <leader>m :cprev<CR>
nnoremap <leader>c :cclose<CR>

let mapleader = 'b'
" show a list of interfaces which is implemented by the type under your cursor
au FileType go nmap <leader>I <Plug>(go-implements)
" show type info for the word under your cursor
au FileType go nmap <leader>gi <Plug>(go-info)
" open the relevant Godoc for the word under the cursor
au FileType go nmap <leader>gd <Plug>(go-doc)
au FileType go nmap <leader>gv <Plug>(go-doc-vertical)
" run Go commands
au FileType go nmap <leader>r <Plug>(go-run)
au FileType go nmap <leader>T <Plug>(go-test)
au FileType go nmap <leader>t <Plug>(go-test-func)
au FileType go nmap <leader>c <Plug>(go-coverage)
au FileType go nmap <leader>i <Plug>(go-install)
au FileType go nmap <leader>dv <Plug>(go-def-vertical)
au FileType go nmap <leader>dt <Plug>(go-def-tab)
au FileType go nmap <leader>ds <Plug>(go-def-stack)
au FileType go nmap <leader>q <Plug>(go-callstack)
au FileType go nmap <leader>h <Plug>(go-referrers)
" rename the identifier under the cursor to a new name
au FileType go nmap <leader>R <Plug>(go-rename)

" run :GoBuild or :GoTestCompile based on the go file
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#test#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction

au FileType go nmap <leader>b :<C-u>call <SID>build_go_files()<CR>

if has("cscope")
    set autochdir
    set tags=tags;
    set cscopetag
    set csre
    set csto=0

    if filereadable("cscope.out")
        cs add cscope.out
    elseif $CSCOPE_DB != ""
        cs add $CSCOPE_DB
    endif
    set cscopeverbose

    nmap zs :cs find s <C-R>=expand("<cword>")<CR><CR>
    nmap zg :cs find g <C-R>=expand("<cword>")<CR><CR>
    nmap zc :cs find c <C-R>=expand("<cword>")<CR><CR>
    nmap zt :cs find t <C-R>=expand("<cword>")<CR><CR>
    nmap ze :cs find e <C-R>=expand("<cword>")<CR><CR>
    nmap zf :cs find f <C-R>=expand("<cfile>")<CR><CR>
    nmap zi :cs find i ^<C-R>=expand("<cfile>")<CR>$<CR>
    nmap zd :cs find d <C-R>=expand("<cword>")<CR><CR>
endif

let mapleader = 'f'
"" EasyMotion Search and jump 
map <leader>e <Plug>(easymotion-overwin-f2)
"" fzf recent files
map <leader>f :FZFMru<CR>
"" fzf file name in this dir
map <leader>d :FZF<CR>
"" fzf file name in project root
map <leader>g :Files `=<sid>GetProjectRoot()`<CR>
"" fzf file content by interaction in project root
map <leader>a :AG <CR>
"" fzf file content by word in project root
map <leader>s :AG <C-R>=expand("<cword>")<CR><CR>

