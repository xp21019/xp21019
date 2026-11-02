#!/bin/bash
# =============================================================================
# Mac 重置後的半自動復原腳本
#
# 用法:
#   /Volumes/隨身硬碟/MacBackup-XXXX/kit/restore.sh /Volumes/隨身硬碟/MacBackup-XXXX
#
# 每一步都會先問你 y/N,按 Enter 預設略過。可以重複執行,不會重複破壞。
# 有些步驟需要輸入 Mac 登入密碼(sudo),這是正常的。
# 隱私權限(輔助使用、螢幕錄製…)macOS 不允許腳本代勾,最後會列出清單請你手動開。
# =============================================================================

set -o pipefail

if [ $# -lt 1 ] || [ ! -d "$1/system" ]; then
  echo "用法:$0 /Volumes/隨身硬碟/MacBackup-XXXX(要指到含 system/ 的那層資料夾)" >&2
  exit 1
fi
B="${1%/}"
SAFETY="$HOME/restore-safety-backup-$(date +%Y%m%d-%H%M%S)"

ask() {
  printf '\n\033[1m%s\033[0m [y/N] ' "$1"
  read -r a
  case "$a" in y|Y|yes|YES) return 0 ;; *) echo "  略過。"; return 1 ;; esac
}

# 覆蓋前先把現有檔案搬到 $SAFETY,出錯可以換回來
keep_old() {
  if [ -e "$1" ]; then
    mkdir -p "$SAFETY$(dirname "$1")"
    cp -R "$1" "$SAFETY$1"
  fi
}

echo "從備份還原:$B"
echo "--- 備份時的系統 ---"
cat "$B/system/sw_vers.txt" 2>/dev/null
cat "$B/system/identity.txt" 2>/dev/null
echo "--- 目前的系統 ---"
sw_vers
echo "若 macOS 主版本不同,偏好設定匯入(步驟 6)請謹慎,只匯入你需要的。"

# 1. 電腦名稱 -----------------------------------------------------------------
if ask "1. 還原電腦名稱(Parsec 主機列表顯示的名字)?"; then
  for k in ComputerName LocalHostName HostName; do
    v=$(grep "^$k=" "$B/system/identity.txt" | cut -d= -f2-)
    [ -n "$v" ] && sudo scutil --set "$k" "$v" && echo "  $k = $v"
  done
fi

# 2. Homebrew ------------------------------------------------------------------
if [ -f "$B/homebrew/Brewfile" ] && ask "2. 安裝 Homebrew 並依 Brewfile 安裝所有套件與 App?"; then
  if ! command -v brew > /dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    if [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
  fi
  echo "  Brewfile 內容如下,可先檢查:"
  sed 's/^/    /' "$B/homebrew/Brewfile" | head -80
  if ask "   確定要執行 brew bundle?"; then
    brew bundle --file="$B/homebrew/Brewfile" || echo "  部分套件失敗,請看上方訊息後手動補裝。"
  fi
fi

# 3. Parsec --------------------------------------------------------------------
if [ -d "$B/streaming/parsec-home" ] && ask "3. 還原 Parsec 設定(~/.parsec)?請先確認 Parsec 已安裝並「完全結束」。"; then
  if pgrep -i parsec > /dev/null; then
    echo "  Parsec 仍在執行,請從選單列結束 Parsec 後再跑一次這步。"
  else
    keep_old "$HOME/.parsec"
    mkdir -p "$HOME/.parsec"
    rsync -a "$B/streaming/parsec-home/" "$HOME/.parsec/"
    echo "  完成。開啟 Parsec 後需要重新登入帳號(登入權杖沒有備份)。"
  fi
fi

# 4. 其他串流相關軟體設定 ------------------------------------------------------
restore_dir() { # 名稱 目的地
  if [ -d "$B/streaming/$1" ] && ask "4. 還原 $1 設定到 $2 ?(請先結束該 App)"; then
    keep_old "$2"; mkdir -p "$2"; rsync -a "$B/streaming/$1/" "$2/"
  fi
}
restore_dir moonlight      "$HOME/Library/Application Support/Moonlight Game Streaming Project"
restore_dir sunshine       "$HOME/.config/sunshine"
restore_dir obs-studio     "$HOME/Library/Application Support/obs-studio"
restore_dir steam-config   "$HOME/Library/Application Support/Steam/config"
restore_dir betterdisplay  "$HOME/Library/Application Support/BetterDisplay"
restore_dir karabiner      "$HOME/.config/karabiner"

if ls "$B/streaming/plists/"*.plist > /dev/null 2>&1 && ask "5. 匯入串流相關 App 的偏好設定 plist?"; then
  for f in "$B/streaming/plists/"*.plist; do
    d=$(basename "$f" .plist)
    if ask "   匯入 $d ?"; then
      mkdir -p "$SAFETY"; defaults export "$d" "$SAFETY/$d.plist" 2>/dev/null
      defaults import "$d" "$f" && echo "   已匯入 $d"
    fi
  done
fi

# 6. 系統偏好設定 --------------------------------------------------------------
if ask "6. 逐一匯入系統偏好設定(Dock、Finder、觸控板…)?"; then
  for f in "$B/prefs/"*.plist; do
    d=$(basename "$f" .plist)
    if ask "   匯入 $d ?"; then
      mkdir -p "$SAFETY"
      defaults export "$d" "$SAFETY/$d.plist" 2>/dev/null
      defaults import "$d" "$f" && echo "   已匯入 $d"
    fi
  done
  killall Dock Finder SystemUIServer 2>/dev/null
  echo "  部分設定需登出再登入才會生效。"
fi

# 7. Shell 設定檔 --------------------------------------------------------------
if ls -A "$B/dotfiles" > /dev/null 2>&1 && ask "7. 還原 Shell 設定檔(.zshrc、.gitconfig、ssh config…)?"; then
  for f in "$B/dotfiles/".[!.]*; do
    [ -f "$f" ] || continue
    keep_old "$HOME/$(basename "$f")"
    cp "$f" "$HOME/" && echo "  $(basename "$f")"
  done
  if [ -d "$B/dotfiles/ssh" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    for f in config known_hosts; do
      [ -f "$B/dotfiles/ssh/$f" ] && keep_old "$HOME/.ssh/$f" && cp "$B/dotfiles/ssh/$f" "$HOME/.ssh/" && chmod 600 "$HOME/.ssh/$f"
    done
  fi
fi

# 8. 字型 ----------------------------------------------------------------------
if [ -n "$(ls -A "$B/fonts" 2>/dev/null)" ] && ask "8. 還原字型?"; then
  mkdir -p "$HOME/Library/Fonts"; cp -R "$B/fonts/." "$HOME/Library/Fonts/"
fi

# 9. 開機啟動 ------------------------------------------------------------------
if [ -d "$B/startup/user-LaunchAgents" ] && ask "9. 還原使用者 LaunchAgents(背景自動啟動的服務)?"; then
  mkdir -p "$HOME/Library/LaunchAgents"
  for f in "$B/startup/user-LaunchAgents/"*.plist; do
    [ -f "$f" ] || continue
    if ask "   還原 $(basename "$f") ?(對應的程式需已安裝)"; then
      cp "$f" "$HOME/Library/LaunchAgents/"
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$(basename "$f")" 2>/dev/null \
        || echo "   載入失敗,可能程式還沒裝,重開機後會再試。"
    fi
  done
fi
if [ -s "$B/startup/login-items.txt" ]; then
  echo
  echo "登入項目(開機自動開啟的 App),備份時有:"
  tr ',' '\n' < "$B/startup/login-items.txt" | sed 's/^ */  - /'
  if ask "   要把仍存在於 /Applications 的這些 App 加回登入項目?"; then
    tr ',' '\n' < "$B/startup/login-items.txt" | sed 's/^ *//' | while read -r app; do
      [ -n "$app" ] || continue
      if [ -d "/Applications/$app.app" ]; then
        osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$app.app\", hidden:false}" > /dev/null \
          && echo "   已加入 $app"
      else
        echo "   找不到 /Applications/$app.app,請手動加入"
      fi
    done
  fi
fi

# 10. 電源 ---------------------------------------------------------------------
if [ -f "$B/power/pmset-custom.txt" ]; then
  echo; echo "備份時的電源設定:"; sed 's/^/  /' "$B/power/pmset-custom.txt"
  if ask "10. 套用串流主機建議的電源設定(接電源時不睡眠、螢幕關閉但主機醒著、網路喚醒)?"; then
    sudo pmset -c sleep 0 disksleep 0 womp 1 autorestart 1 powernap 0
    echo "  已套用。若備份時的數值不同,可參考上面的清單用 sudo pmset 個別調整。"
  fi
fi

# 11. 顯示器 -------------------------------------------------------------------
if [ -s "$B/display/displayplacer-restore-command.txt" ]; then
  echo; echo "顯示器排列還原指令:"; cat "$B/display/displayplacer-restore-command.txt"
  if command -v displayplacer > /dev/null 2>&1 && ask "11. 執行上面的指令還原顯示器解析度與排列?(需接上相同的螢幕)"; then
    eval "$(cat "$B/display/displayplacer-restore-command.txt")"
  fi
fi

# 12. 網路 ---------------------------------------------------------------------
echo
echo "網路設定(DNS、固定 IP 等)請對照 $B/network/service-details.txt。"
echo "防火牆設定請對照 $B/network/firewall.txt。"
if grep -q 'enabled' "$B/network/firewall.txt" 2>/dev/null && ask "12. 開啟防火牆?(Parsec 首次啟動時請按「允許傳入連線」)"; then
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
fi

# 13. 權限提醒 -----------------------------------------------------------------
cat <<'EOF'

================== 需要你手動完成的項目 ==================
到「系統設定 > 隱私權與安全性」,替 Parsec(及其他串流 App)開啟:
  [ ] 螢幕錄製(Screen & System Audio Recording)— 對方才看得到畫面
  [ ] 輔助使用(Accessibility)— 對方才能操控滑鼠鍵盤
  [ ] 麥克風(Microphone)— 需要語音時
  [ ] 輸入監控(Input Monitoring)— 部分版本需要
開啟後請「完全結束」Parsec 再重開,權限才會生效。

其他:
  [ ] 登入 Parsec 帳號(含兩步驟驗證)
  [ ] 依 MANUAL-SECRETS.md 輸入各項密碼/金鑰
  [ ] 系統設定 > 一般 > 登入項目:確認 Parsec 有在清單中
==========================================================
EOF
[ -f "$B/permissions/tcc-user.tsv" ] && echo "備份時的權限清單:$B/permissions/tcc-user.tsv"
[ -d "$SAFETY" ] && echo "被覆蓋的舊檔已存放在:$SAFETY"
echo "復原腳本結束。"
