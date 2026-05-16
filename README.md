# dotfiles

macOS 用 dotfiles。chezmoi + mise で管理。

## セットアップ(新マシン)

```sh
# 1. Homebrew インストール(未導入なら)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. mise インストール
brew install mise

# 3. リポ取得(両方 clone)
mkdir -p ~/ghq/github.com/Hirayama61
cd ~/ghq/github.com/Hirayama61
git clone git@github.com:Hirayama61/dotfiles.git
git clone git@github.com:Hirayama61/cc-dotfiles.git

# 4. ブートストラップ(brew bundle + chezmoi config 配置)
cd dotfiles
mise run bootstrap

# 5. ~/.config/chezmoi/dotfiles.toml の [data] にマシン固有値(email等)を編集

# 6. 適用
mise run apply
```

## 日常運用

```sh
mise run apply            # 両リポ適用
mise run apply:dotfiles   # このリポのみ
mise run apply:cc-dotfiles     # cc-dotfiles のみ
mise run diff             # 適用前差分
mise run update           # git pull → apply
```

## 構成

詳細は [CLAUDE.md](./CLAUDE.md) を参照。
