# =============================================================================
# 1. Powerlevel10k Instant Prompt (必須放在最上方)
# =============================================================================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# =============================================================================
# 2. Zinit 初始化 (Plugin Manager)
# =============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)" && \
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"

source "${ZINIT_HOME}/zinit.zsh"

# =============================================================================
# 3. 載入 Powerlevel10k 主題
# =============================================================================
zinit ice depth=1
zinit light romkatv/powerlevel10k

# =============================================================================
# 4. 核心 OMZ 庫
# =============================================================================
# 建議將 history/key-bindings/completion 改為 snippet (立即載入)
# 以避免剛啟動時沒有歷史紀錄或補全的問題
zinit snippet OMZ::lib/git.zsh
zinit snippet OMZ::lib/completion.zsh
zinit snippet OMZ::lib/history.zsh
zinit snippet OMZ::lib/key-bindings.zsh
zinit snippet OMZ::lib/theme-and-appearance.zsh
zinit snippet OMZ::lib/clipboard.zsh

# =============================================================================
# 5. 載入插件 (Plugins)
# =============================================================================

# --- 來自 GitHub 的插件 ---
zinit wait lucid for \
    Aloxaf/fzf-tab \
    agkozak/zsh-z \
    MichaelAquilina/zsh-you-should-use \
    fdellwing/zsh-bat \
    zsh-users/zsh-completions

# 注意：zsh-autosuggestions 需要在 syntax-highlighting 之前載入
zinit wait lucid atload"_zsh_autosuggest_start" for \
    zsh-users/zsh-autosuggestions

# --- 來自 Oh-My-Zsh 的插件 (Snippets) ---
zinit wait lucid for \
    OMZ::plugins/git/git.plugin.zsh \
    OMZ::plugins/tmux/tmux.plugin.zsh \
    OMZ::plugins/docker/docker.plugin.zsh \
    OMZ::plugins/fzf/fzf.plugin.zsh \
    OMZ::plugins/extract/extract.plugin.zsh

# =============================================================================
# 6. 高亮與 Vim 模式 (必須放在最後)
# =============================================================================

# 1. Syntax Highlighting (必須在 autosuggestions 之後，並在最後初始化補全)
zinit wait lucid atinit"zicompinit; zicdreplay" for \
    zsh-users/zsh-syntax-highlighting

# 2. Zsh-Vi-Mode (必須最後載入，以正確覆蓋按鍵)
zinit ice depth=1
zinit light jeffreytse/zsh-vi-mode

# Define an init function and append to zvm_after_init_commands
function my_init() {
  zvm_bindkey viins '^F' autosuggest-accept
  # 恢復原本的歷史搜尋按鍵 (Ctrl+P / Ctrl+N)
  # 使用 up-line-or-search 可以根據已輸入的前綴搜尋歷史
  zvm_bindkey viins '^P' up-line-or-search
  zvm_bindkey viins '^N' down-line-or-search
}
zvm_after_init_commands+=(my_init)

# =============================================================================
# 7. 用戶自定義設定 (User Configuration)
# =============================================================================

# History behavior
setopt HIST_IGNORE_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# Aliases
alias v='$EDITOR'
alias avante='nvim -c "lua vim.defer_fn(function()require(\"avante.api\").zen_mode()end, 100)"'
alias ll='eza --all --long'
alias ls='eza --all'
alias grep='rg --color always --heading --line-number'
alias cat='bat'

# Suffix aliases
alias -s {md,txt,log,py,js,ts,go,rs,c,cpp,h,hpp,tex,html,config}='$EDITOR'

# 注意：原本這裡的 bindkey 已經移到上面的 zvm_after_init 函數中了

# Autosuggest 設定
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# =============================================================================
# 8. Conda 初始化
# =============================================================================
# 根據系統自動偵測 conda 路徑
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    CONDA_BASE="/opt/homebrew/Caskroom/miniconda/base"
elif [[ -d "$HOME/miniconda3" ]]; then
    # Linux - 用戶安裝的 miniconda
    CONDA_BASE="$HOME/miniconda3"
elif [[ -d "$HOME/anaconda3" ]]; then
    # Linux - 用戶安裝的 anaconda
    CONDA_BASE="$HOME/anaconda3"
elif [[ -d "/opt/miniconda3" ]]; then
    # Linux - 系統級安裝
    CONDA_BASE="/opt/miniconda3"
fi

if [[ -n "$CONDA_BASE" && -f "$CONDA_BASE/bin/conda" ]]; then
    __conda_setup="$("$CONDA_BASE/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
            . "$CONDA_BASE/etc/profile.d/conda.sh"
        else
            export PATH="$CONDA_BASE/bin:$PATH"
        fi
    fi
    unset __conda_setup
fi
unset CONDA_BASE

# =============================================================================
# 9. P10k 設定檔讀取
# =============================================================================
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh