# Dotfiles put under linux home

This repo includes handy configurations for bash, git, vim.
And neovim config is mainly from:
* [glepnir-nvim](https://github.com/glepnir-nvim)

## Usage
1. Setup backup sudoers
```
sudo useradd --system -p PASSWORD -G sudo `whoami`2
```
2. Docker
```
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -a -G docker `whoami`
newgrp docker
```
3. Install zsh, oh-my-zsh
```
sudo apt install zsh -y
sudo chsh -s $(which zsh)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/agkozak/zsh-z ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
```
4. Put dotfiles to ${HOME}
```
git clone git@github.com:ui-HookeyChiang/dotfiles.git
cd dotfiles
git submodule update --init
cp -r .* ~
cd ..
```
5. Install nvim and prerequisites for plugins
* if the host is arm64
```
sudo apt install -y cmake gettext clang
git clone https://github.com/neovim/neovim.git
cd neovim
make CMAKE_BUILD_TYPE=RelWithDebInfo
sudo make install
sudo apt install clangd
ln -s /usr/bin/clangd ~/.local/share/nvim/mason/bin/clangd
mkdir ~/.local/share/nvim/mason/packages/clangd
```
* if the host is x86_64
```
curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim.appimage
chmod u+x nvim.appimage
./nvim.appimage --appimage-extract
sudo rm -rf /squashfs-root
sudo mv squashfs-root /
sudo ln -s /squashfs-root/AppRun /usr/bin/nvim
rm nvim.appimage
```
* Install the prerequisites
```
sudo apt install -y python3-venv python3-pip clang npm unzip ripgrep fzf bat fd-find
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
npm install typescript
sudo snap install go --classic
go install github.com/segmentio/golines@latest
sudo apt install cargo
cargo install stylua rustfmt
sudo apt install git-buildpackage
```
6. Install tmux
```
sudo apt install tmux
git clone https://github.com/gpakosz/.tmux.git ~/.oh-my-tmux
mkdir -p ~/.config/tmux
ln -s ~/.oh-my-tmux/.tmux.conf ~/.config/tmux/tmux.conf
cp ~/.oh-my-tmux/.tmux.conf.local ~/.config/tmux/tmux.conf.local
cat ~/.config/tmux.default/.tmux.conf.local >> ~/.config/tmux/tmux.conf.local
```
7. Install [aicommits](https://github.com/Nutlope/aicommits)
```
npm install -g aicommits
aicommits config set OPENAI_KEY=<your token> max-length=60
```
8. Install [Latexmk](https://mg.readthedocs.io/latexmk.html),
9. Install [PDF Reader](https://ejmastnak.com/tutorials/vim-latex/pdf-reader/#zathura-macos) for latex
- skim and texsync
```
brew install skim
PDF-TeX cmd=nvim args=--headless -c "VimtexInverseSearch %line '%file'"
```
- [zathura](https://github.com/zegervdv/homebrew-zathura)
```
nvim :help vimtex-faq-zathura-macos
```
