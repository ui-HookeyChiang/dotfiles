# Canonical compdump path — prevents race-suffix dumps (~/.zcompdump.host.pid) from accumulating
: ${ZSH_COMPDUMP:=$HOME/.zcompdump-${ZSH_VERSION}}

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
zinit snippet OMZ::lib/completion.zsh
zinit snippet OMZ::lib/history.zsh
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
zinit wait lucid atload'!_zsh_autosuggest_start' for \
    zsh-users/zsh-autosuggestions

# --- 來自 Oh-My-Zsh 的插件 (Snippets) ---
zinit wait lucid for \
    OMZ::plugins/git/git.plugin.zsh \
    OMZ::plugins/tmux/tmux.plugin.zsh \
    OMZ::plugins/fzf/fzf.plugin.zsh \
    OMZ::plugins/extract/extract.plugin.zsh

# =============================================================================
# 6. 高亮與 Vim 模式 (必須放在最後)
# =============================================================================

# 1. Syntax Highlighting (必須在 autosuggestions 之後，並在最後初始化補全)
zinit wait lucid atinit"zicompinit -C -d \"\$ZSH_COMPDUMP\"; zicdreplay" for \
    zsh-users/zsh-syntax-highlighting

# 2. Zsh-Vi-Mode (必須最後載入，以正確覆蓋按鍵)
zinit ice depth=1
zinit light jeffreytse/zsh-vi-mode

# Define an init function and append to zvm_after_init_commands
function my_init() {
  # Existing user bindings
  zvm_bindkey viins '^F' autosuggest-accept
  zvm_bindkey viins '^P' up-line-or-search
  zvm_bindkey viins '^N' down-line-or-search

  # Restore productive bindings previously from OMZ::lib/key-bindings.zsh
  # (verified safe by PTY A/B test — 0 viins/vicmd regression)

  autoload -U edit-command-line; zle -N edit-command-line
  zvm_bindkey viins '^X^E' edit-command-line
  bindkey -M vicmd '^X^E' edit-command-line

  autoload -U up-line-or-beginning-search; zle -N up-line-or-beginning-search
  zvm_bindkey viins '^[[A' up-line-or-beginning-search
  zvm_bindkey viins '^[OA' up-line-or-beginning-search
  bindkey -M vicmd '^[[A' up-line-or-beginning-search
  bindkey -M vicmd '^[OA' up-line-or-beginning-search

  autoload -U down-line-or-beginning-search; zle -N down-line-or-beginning-search
  zvm_bindkey viins '^[[B' down-line-or-beginning-search
  zvm_bindkey viins '^[OB' down-line-or-beginning-search
  bindkey -M vicmd '^[[B' down-line-or-beginning-search
  bindkey -M vicmd '^[OB' down-line-or-beginning-search

  if [[ -n "${terminfo[kcbt]}" ]]; then
    zvm_bindkey viins "${terminfo[kcbt]}" reverse-menu-complete
    bindkey -M vicmd "${terminfo[kcbt]}" reverse-menu-complete
  fi

  zvm_bindkey viins '^[[3;5~' kill-word
  bindkey -M vicmd '^[[3;5~' kill-word

  zvm_bindkey viins '^[[1;5C' forward-word
  zvm_bindkey viins '^[[1;5D' backward-word
  bindkey -M vicmd '^[[1;5C' forward-word
  bindkey -M vicmd '^[[1;5D' backward-word

  if [[ -n "${terminfo[kpp]}" ]]; then
    zvm_bindkey viins "${terminfo[kpp]}" up-line-or-history
    bindkey -M vicmd "${terminfo[kpp]}" up-line-or-history
  fi
  if [[ -n "${terminfo[knp]}" ]]; then
    zvm_bindkey viins "${terminfo[knp]}" down-line-or-history
    bindkey -M vicmd "${terminfo[knp]}" down-line-or-history
  fi
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

# Linux: bridge Ubuntu/Debian's renamed fd binary (fdfind) to the universal name
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi

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

# Rust/cargo binaries (stylua, tree-sitter, etc.) — needed by nvim formatters/treesitter
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

# =============================================================================
# 9. Terminal true color
# =============================================================================
export COLORTERM=truecolor

# =============================================================================
# 10. P10k 設定檔讀取
# =============================================================================
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

# opencode
export PATH=/home/hookey/.opencode/bin:$PATH
export OPENCODE_SERVER_URL="http://127.0.0.1:4096"

# oc — attach to shared opencode server (all sessions visible to telegram-claude-bridge bot)
# Uses --dir $(pwd) so each project opens in its own working directory.
# Falls back to local TUI if server not reachable.
oc() {
  if curl -s --max-time 1 "$OPENCODE_SERVER_URL/session" > /dev/null 2>&1; then
    /home/hookey/.opencode/bin/opencode attach "$OPENCODE_SERVER_URL" --dir "$(pwd)" "$@"
  else
    echo "[oc] server not reachable at $OPENCODE_SERVER_URL, starting local opencode" >&2
    /home/hookey/.opencode/bin/opencode "$@"
  fi
}

# Skip folder-trust + one-time bypass-mode confirm for worktree-driven AFK sessions.
# Deliberate CLI-flag-only escape hatch (no settings.json equivalent by design).
alias claude='claude --dangerously-skip-permissions'
