# Brewfile
#
# このファイルには **bootstrap 用 CLI** と **GUI cask アプリ** のみを置く。
# CLI ツールは原則 chezmoi(設定)+ mise/Homebrew(本体)で個別管理する。
#
# 適用: `brew bundle --file=./Brewfile`
# 現状から再生成: `brew bundle dump --force --file=./Brewfile`

# Bootstrap CLI(mise.toml の前提となる、最低限の手動インストール用)
brew "mise"           # task runner / runtime version manager

# CLI(mise レジストリに無いもの)
brew "tig"            # git TUI

# GUI Apps
cask "ghostty"        # ターミナルエミュレータ
cask "zed"            # エディタ
cask "raycast"        # ランチャー / Spotlight 代替
cask "coderabbit"     # CLI レビュー本体。/self-review と /coderabbit:review が利用
# codex は個人PC専用のため Brewfile に含めない(導入: mise run setup:codex)
cask "obsidian"       # 永続記憶 vault(~/obsidian/brain)の閲覧 / グラフ表示

# Fonts
cask "font-jetbrains-mono-nerd-font"  # Ghostty フォント(可読性重視・Nerd Font アイコン込み)
