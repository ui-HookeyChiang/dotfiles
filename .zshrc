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
# 使用 depth=1 加速下載
zinit ice depth=1
zinit light romkatv/powerlevel10k

# =============================================================================
# 4. 核心 OMZ 庫 (模擬 Oh-My-Zsh 的基礎功能)
# =============================================================================
# 如果你依賴 OMZ 的一些預設行為 (如剪貼簿處理、基本補全設定)，這些 Snippet很有用
zinit wait lucid for \
    OMZ::lib/git.zsh \
    OMZ::lib/completion.zsh \
    OMZ::lib/history.zsh \
    OMZ::lib/key-bindings.zsh \
    OMZ::lib/theme-and-appearance.zsh

# =============================================================================
# 5. 載入插件 (Plugins)
# =============================================================================
# wait: 非同步加載 (Turbo mode)
# lucid: 加載完成後不顯示報告 (靜默模式)
# atload: 加載後執行的命令

# --- 來自 GitHub 的插件 ---
zinit wait lucid for \
    agkozak/zsh-z \
    MichaelAquilina/zsh-you-should-use \
    fdellwing/zsh-bat \
    zsh-users/zsh-completions \
    zsh-users/zsh-autosuggestions

# --- 來自 Oh-My-Zsh 的插件 (Snippets) ---
# Zinit 可以直接只抓取 OMZ 的特定插件資料夾，而不需下載整個框架
zinit wait lucid for \
    OMZ::plugins/git/git.plugin.zsh \
    OMZ::plugins/tmux/tmux.plugin.zsh \
    OMZ::plugins/tig/tig.plugin.zsh \
    OMZ::plugins/docker/docker.plugin.zsh \
    OMZ::plugins/extract/extract.plugin.zsh \
    OMZ::plugins/fzf/fzf.plugin.zsh

# --- 語法高亮 (必須最後加載) ---
# atinit: 初始化時執行
zinit wait lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" for \
    zsh-users/zsh-syntax-highlighting

# =============================================================================
# 6. 用戶自定義設定 (User Configuration)
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

# Suffix aliases (直接輸入檔名開啟)
alias -s json=jless
alias -s md='$EDITOR'
alias -s go='$EDITOR'
alias -s rs='$EDITOR'
alias -s txt='$EDITOR'
alias -s log='$EDITOR'
alias -s py='$EDITOR'
alias -s js='$EDITOR'
alias -s ts='$EDITOR'

# Keybindings
bindkey "^P" history-beginning-search-backward
bindkey "^N" history-beginning-search-forward

# Autosuggest 設定
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# =============================================================================
# 7. Conda 初始化
# =============================================================================
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup

# =============================================================================
# 8. P10k 設定檔讀取
# =============================================================================
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
