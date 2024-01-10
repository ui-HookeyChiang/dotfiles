# Dotfiles put under linux home

This repo includes handy configurations for bash, git, vim.
And neovim config is mainly from:
* [glepnir-nvim](https://github.com/glepnir-nvim)

## Usage

1. Simply put files to ${HOME}
2. Install zsh, oh-my-zsh
```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
```
3. Install nvim and prerequisites for plugins
```
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage\nchmod u+x nvim.appimage\n./nvim.appimage
sudo mv squashfs-root /\nsudo ln -s /squashfs-root/AppRun /usr/bin/nvim
sudo apt install -y python3-venv clang npm unzip ripgrep
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
npm install typescript
```
4. Install tmux
```
apt install tmux
```
