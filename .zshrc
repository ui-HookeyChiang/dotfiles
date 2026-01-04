# =============================================================================
# 1. Powerlevel10k Instant Prompt (保持最頂端，效能關鍵)
# =============================================================================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# =============================================================================
# 2. Zinit 初始化
# =============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)" && \
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"

source "${ZINIT_HOME}/zinit.zsh"

# =============================================================================
# 3. 核心體驗與主題 (Theme & Core)
# =============================================================================
# Powerlevel10k 主題
zinit ice depth=1
zinit light romkatv/powerlevel10k

# OMZ 核心庫 (剪貼簿、目錄操作等基礎功能)
zinit wait lucid for \
    OMZ::lib/clipboard.zsh \
    OMZ::lib/directories.zsh \
    OMZ::lib/git.zsh \
    OMZ::lib/theme-and-appearance.zsh

# =============================================================================
# 4. 現代化補全系統 (Completion & FZF-Tab)
# =============================================================================
# 加載補全庫
zinit wait lucid for \
    zsh-users/zsh-completions

# FZF-Tab: 用 fzf 取代傳統 Tab 補全選單 (強烈推薦)
# 必須在 compinit 之後，autosuggestions 之前載入
zinit ice wait lucid blockf
zinit light Aloxaf/fzf-tab

# FZF-Tab 配置: 預覽目錄內容、檔案內容
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 {}'

# =============================================================================
# 5. 功能插件 (Plugins)
# =============================================================================

# --- 工具類 ---
# Zoxide: 比 z 更快的目錄跳轉工具 (需 brew install zoxide)
zinit ice wait lucid as"command" from"gh-r" \
    atclone"./zoxide init zsh > init.zsh" \
    atpull"%atclone" src"init.zsh"
zinit light ajeetdsouza/zoxide

# Bat: 帶語法高亮的 cat (顯示檔案內容)
zinit wait lucid for fdellwing/zsh-bat

# You Should Use: 提醒你有更好的 alias 可以用
zinit wait lucid for MichaelAquilina/zsh-you-should-use

# Autosuggestions: 根據歷史紀錄建議指令
zinit wait lucid for zsh-users/zsh-autosuggestions

# --- OMZ 插件 (Snippets) ---
zinit wait lucid for \
    OMZ::plugins/git/git.plugin.zsh \
    OMZ::plugins/tmux/tmux.plugin.zsh \
    OMZ::plugins/docker/docker.plugin.zsh \
    OMZ::plugins/extract/extract.plugin.zsh \
    OMZ::plugins/sudo/sudo.plugin.zsh \
    OMZ::plugins/fzf/fzf.plugin.zsh

# =============================================================================
# 6. 高亮與 Vim 模式 (Syntax Highlighting & Vi Mode)
# =============================================================================
# 注意：順序很重要
# 1. Syntax Highlighting 必須在 Autosuggestions 之後，但在 Vi-Mode 之前
# 2. Vi-Mode 必須最後載入以正確覆蓋按鍵綁定

zinit wait lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" for \
    zsh-users/zsh-syntax-highlighting

zinit ice depth=1
zinit light jeffreytse/zsh-vi-mode

# 修復 Vi-Mode 與 Autosuggestions 的衝突
function zvm_after_init() {
  zvm_bindkey viins '^F' autosuggest-accept
  zvm_bindkey viins '^P' history-search-backward
  zvm_bindkey viins '^N' history-search-forward
}

# =============================================================================
# 7. 一般設定 (Settings)
# =============================================================================
# 歷史紀錄設定
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS  # 移除重複紀錄
setopt HIST_SAVE_NO_DUPS     # 不儲存重複紀錄
setopt HIST_REDUCE_BLANKS    # 移除多餘空白
setopt SHARE_HISTORY         # 視窗間共享歷史
setopt INC_APPEND_HISTORY    # 立即寫入歷史檔案

# 一般 Aliases
alias v='$EDITOR'
alias avante='nvim -c "lua vim.defer_fn(function()require(\"avante.api\").zen_mode()end, 100)"'
# 使用 eza 替代 ls (加上圖示與 git 狀態)
alias ls='eza --icons --git --group-directories-first'
alias ll='eza --all --long --icons --git --group-directories-first'
alias tree='eza --tree --icons'
alias grep='rg --color always --heading --line-number'
alias cat='bat'

# 快速開啟檔案 (Suffix Aliases)
alias -s {json,yaml,yml}=jless
alias -s {md,txt,log,py,js,ts,go,rs,c,cpp,h,hpp,tex,html}='$EDITOR'

# =============================================================================
# 8. 環境變數與外部工具 (Exports & External)
# =============================================================================
export EDITOR='nvim'
export LANG=en_US.UTF-8

# Conda 初始化
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

# P10k 設定
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
