#!/usr/bin/env bash
# macOS defaults / pmset / nvram を一括設定する。
#
# 想定: 新マシン bootstrap 時に1回だけ実行。日常運用では走らせない。
# 実行: mise run macos
#
# sudo パスワードを途中で求められる(pmset / nvram のため)。
# 適用後、Finder / Dock / SystemUIServer を kill して再読み込みする。

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS 専用スクリプトです。skip。" >&2
  exit 0
fi

echo "==> sudo を先に取得(後段で pmset / nvram に使う)"
sudo -v
PARENT_PID=$$
while true; do sudo -n true; sleep 60; kill -0 "$PARENT_PID" 2>/dev/null || exit; done &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ─── Finder ────────────────────────────────────────────
echo "==> Finder"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# ─── Dock ──────────────────────────────────────────────
echo "==> Dock"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.2
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock mineffect -string "scale"

# ─── Keyboard / Trackpad ───────────────────────────────
echo "==> Keyboard / Trackpad"
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# ─── Global UI ─────────────────────────────────────────
echo "==> Global UI"
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
defaults write com.apple.menuextra.clock ShowSeconds -bool true
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# ─── 書類ごとの入力ソース ──────────────────────────────
echo "==> Document input source sync"
defaults write NSGlobalDomain AppleEnableDocumentInputSourceSync -bool true

# ─── Spotlight ショートカット無効化 ────────────────────
# 64 = Show Spotlight search (Cmd+Space)
# 65 = Show Finder search window (Cmd+Opt+Space)
# Raycast に Cmd+Space を譲る目的。
# メニューバーアイコン非表示は GUI(System Settings > Control Center > Spotlight)で。
echo "==> Spotlight shortcuts off"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \
  "<dict><key>enabled</key><false/></dict>"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 \
  "<dict><key>enabled</key><false/></dict>"
# 即時反映のため activateSettings を reload(失敗しても無害)
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true

# ─── .DS_Store 抑止 ────────────────────────────────────
echo "==> .DS_Store 抑止"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# ─── 起動音 OFF ────────────────────────────────────────
echo "==> 起動音 OFF (nvram, sudo)"
sudo nvram StartupMute=%01

# 蓋閉じスリープ抑止については `pmset disablesleep` を試したが、
# `-c` 指定が無視され system-wide 適用となるため battery 時もスリープしなくなる。
# 外部ディスプレイ + 電源 + 外部入力デバイス接続時の clamshell mode に任せる方針で
# pmset は触らない。

# ─── 反映 ──────────────────────────────────────────────
echo "==> Finder / Dock / SystemUIServer を再起動"
killall Finder         2>/dev/null || true
killall Dock           2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo
echo "完了。一部設定はログアウト/再起動で反映されます。"
