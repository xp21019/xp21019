#!/bin/bash
# =============================================================================
# Mac 重置前一鍵備份腳本(串流軟體 + 系統設定)
#
# 用法:
#   ./backup.sh /Volumes/你的隨身硬碟名稱
#
# 會在隨身硬碟建立 MacBackup-YYYYMMDD-HHMMSS/ 資料夾,內含:
#   設定檔、plist、Brewfile、App 清單、網路/顯示器/電源資訊、權限清單,
#   以及本復原包本身(README.md、restore.md、restore.sh),讓隨身硬碟可獨立使用。
#
# 安全原則:不備份密碼、金鑰、登入權杖(token)。這些列在 MANUAL-SECRETS.md
# 由你重置後手動輸入。
#
# 相容 macOS 內建的 bash 3.2(不使用關聯陣列、mapfile 等新語法)。
# =============================================================================

set -o pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "此腳本只能在 macOS 上執行。" >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "用法:$0 /Volumes/隨身硬碟名稱" >&2
  echo "目前接上的磁碟:" >&2
  ls /Volumes >&2
  exit 1
fi

TARGET_ROOT="${1%/}"
if [ ! -d "$TARGET_ROOT" ] || [ ! -w "$TARGET_ROOT" ]; then
  echo "找不到或無法寫入:$TARGET_ROOT" >&2
  exit 1
fi

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TARGET_ROOT/MacBackup-$STAMP"
LOG="$OUT/backup.log"

mkdir -p "$OUT"/{system,apps,homebrew,streaming,prefs,network,display,power,startup,permissions,dotfiles,fonts,audio,kit}
: > "$LOG"

say()  { printf '\n==> %s\n' "$*" | tee -a "$LOG"; }
note() { printf '    %s\n' "$*" | tee -a "$LOG"; }

# run <輸出檔> <指令...>:執行指令、把結果寫進檔案,失敗只記錄不中斷
run() {
  local outfile="$1"; shift
  if "$@" > "$outfile" 2>> "$LOG"; then
    return 0
  else
    echo "    [失敗,已略過] $*" >> "$LOG"
    return 1
  fi
}

# 匯出某個 defaults 網域成 XML plist(可讀、可用 defaults import 還原)
export_domain() {
  local domain="$1" dest="$2"
  if defaults read "$domain" > /dev/null 2>&1; then
    defaults export "$domain" - > "$dest/$domain.plist" 2>> "$LOG" \
      && plutil -convert xml1 "$dest/$domain.plist" 2>> "$LOG"
  fi
}

# 複製資料夾但排除含有登入權杖/金鑰的檔案
safe_copy_dir() {
  local src="$1" dest="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$dest"
  rsync -a \
    --exclude 'user.bin' --exclude '*.key' --exclude '*.pem' --exclude '*.p12' \
    --exclude '*token*' --exclude '*Token*' --exclude '*credential*' --exclude '*Credential*' \
    --exclude '*password*' --exclude '*secret*' --exclude 'Cookies*' --exclude 'Cache*' \
    --exclude 'cache*' --exclude 'logs' --exclude '*.log' --exclude 'GPUCache' \
    --exclude 'sunshine_state.json' --exclude 'credentials' \
    "${src%/}/" "$dest/" >> "$LOG" 2>&1
}

echo "備份目的地:$OUT"
echo "過程約 1~5 分鐘。若跳出「終端機想要存取…」的視窗,請按「允許」。"

# -----------------------------------------------------------------------------
say "1/12 系統資訊(Mac 型號、macOS 版本、晶片)"
run "$OUT/system/sw_vers.txt"      sw_vers
run "$OUT/system/uname.txt"        uname -a
run "$OUT/system/hardware.txt"     system_profiler SPHardwareDataType
run "$OUT/system/software.txt"     system_profiler SPSoftwareDataType
{
  echo "ComputerName=$(scutil --get ComputerName 2>/dev/null)"
  echo "LocalHostName=$(scutil --get LocalHostName 2>/dev/null)"
  echo "HostName=$(scutil --get HostName 2>/dev/null)"
  echo "User=$(whoami)"
  echo "Shell=$SHELL"
  echo "Arch=$(uname -m)"
  echo "BackupDate=$STAMP"
} > "$OUT/system/identity.txt"

# -----------------------------------------------------------------------------
say "2/12 已安裝的 App 清單"
ls -1 /Applications > "$OUT/apps/applications.txt" 2>> "$LOG"
ls -1 "$HOME/Applications" > "$OUT/apps/user-applications.txt" 2>/dev/null
# 每個 App 的版本與 Bundle ID(方便重裝相同版本)
{
  printf 'App\tBundleID\tVersion\n'
  for app in /Applications/*.app "$HOME"/Applications/*.app; do
    [ -d "$app" ] || continue
    plist="$app/Contents/Info.plist"
    bid=$(defaults read "$plist" CFBundleIdentifier 2>/dev/null)
    ver=$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null)
    printf '%s\t%s\t%s\n' "$(basename "$app")" "$bid" "$ver"
  done
} > "$OUT/apps/app-versions.tsv"
if command -v mas > /dev/null 2>&1; then
  run "$OUT/apps/mas-list.txt" mas list
fi

# -----------------------------------------------------------------------------
say "3/12 Homebrew 套件(Brewfile)"
if command -v brew > /dev/null 2>&1; then
  (cd "$OUT/homebrew" && brew bundle dump --force --describe --file=Brewfile >> "$LOG" 2>&1) \
    && note "已產生 Brewfile"
  run "$OUT/homebrew/brew-config.txt" brew config
  run "$OUT/homebrew/brew-leaves.txt" brew leaves
  run "$OUT/homebrew/brew-casks.txt"  brew list --cask --versions
  run "$OUT/homebrew/brew-services.txt" brew services list
else
  note "未安裝 Homebrew,略過"
  echo "此 Mac 未安裝 Homebrew" > "$OUT/homebrew/NOT-INSTALLED.txt"
fi

# -----------------------------------------------------------------------------
say "4/12 串流軟體設定(Parsec 及其他常見串流/虛擬顯示/音訊工具)"
S="$OUT/streaming"

# Parsec:設定在 ~/.parsec(config.txt / config.json);user.bin 是登入權杖,不備份
if [ -d "$HOME/.parsec" ]; then
  safe_copy_dir "$HOME/.parsec" "$S/parsec-home"
  note "已備份 ~/.parsec(已排除登入權杖 user.bin)"
fi
for d in "$HOME/Library/Application Support/Parsec" "$HOME/Library/Application Support/parsec"; do
  [ -d "$d" ] && safe_copy_dir "$d" "$S/parsec-appsupport"
done

# 其他可能用到的串流相關軟體(有裝才會備份)
# 格式:顯示名稱|資料夾路徑
while IFS='|' read -r name path; do
  [ -n "$name" ] || continue
  if [ -e "$path" ]; then
    safe_copy_dir "$path" "$S/$name"
    note "已備份 $name 設定"
  fi
done <<EOF
moonlight|$HOME/Library/Application Support/Moonlight Game Streaming Project
sunshine|$HOME/.config/sunshine
obs-studio|$HOME/Library/Application Support/obs-studio
steam-config|$HOME/Library/Application Support/Steam/config
betterdisplay|$HOME/Library/Application Support/BetterDisplay
karabiner|$HOME/.config/karabiner
EOF

# 所有名稱含串流關鍵字的偏好設定 plist
mkdir -p "$S/plists"
for p in "$HOME"/Library/Preferences/*.plist; do
  base=$(basename "$p" .plist)
  case "$(echo "$base" | tr '[:upper:]' '[:lower:]')" in
    *parsec*|*moonlight*|*sunshine*|*steam*|*obs*|*betterdisplay*|*displaylink*|*blackhole*|*loopback*|*soundflower*|*karabiner*|*jumpdesktop*|*rustdesk*|*chiaki*|*nvidia*|*geforce*|*rainway*|*tailscale*|*zerotier*)
      export_domain "$base" "$S/plists"
      ;;
  esac
done

# 列出所有可能相關的元件,方便判斷要重裝什麼
{
  echo "## 音訊驅動(虛擬音效卡,例如 BlackHole)"
  ls -1 /Library/Audio/Plug-Ins/HAL 2>/dev/null
  echo; echo "## 系統延伸功能 / 驅動"
  systemextensionsctl list 2>/dev/null
  echo; echo "## 核心延伸(kext,舊式驅動)"
  kextstat 2>/dev/null | grep -v com.apple
  echo; echo "## 正在執行的串流相關程序"
  ps axo comm | grep -iE 'parsec|moonlight|sunshine|steam|obs|betterdisplay|tailscale|zerotier' | sort -u
} > "$S/related-components.txt" 2>> "$LOG"

# -----------------------------------------------------------------------------
say "5/12 系統偏好設定(Dock、Finder、鍵盤、觸控板等)"
P="$OUT/prefs"
for domain in \
  NSGlobalDomain com.apple.dock com.apple.finder com.apple.screencapture \
  com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad \
  com.apple.HIToolbox com.apple.Terminal com.apple.universalaccess \
  com.apple.WindowManager com.apple.controlcenter com.apple.menuextra.clock \
  com.apple.Safari com.apple.screensaver com.apple.loginwindow \
  com.apple.symbolichotkeys com.apple.spaces com.apple.inputmethod.Kotoeri \
  com.apple.inputsources com.googlecode.iterm2 com.knollsoft.Rectangle; do
  export_domain "$domain" "$P"
done
# 只記錄所有網域名稱(不整包複製 Preferences,避免把其他 App 的登入權杖帶出去)
defaults domains 2>/dev/null | tr ',' '\n' | sed 's/^ *//' > "$P/all-domains.txt"

# -----------------------------------------------------------------------------
say "6/12 網路設定(服務、IP、DNS、防火牆、Wi-Fi 名稱)"
N="$OUT/network"
run "$N/services.txt"      networksetup -listallnetworkservices
run "$N/service-order.txt" networksetup -listnetworkserviceorder
run "$N/hardware-ports.txt" networksetup -listallhardwareports
networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | sed 's/^\*//' | while read -r svc; do
  [ -n "$svc" ] || continue
  {
    echo "### $svc"
    networksetup -getinfo "$svc"
    echo "DNS:";        networksetup -getdnsservers "$svc"
    echo "SearchDomains:"; networksetup -getsearchdomains "$svc"
    echo "WebProxy:";   networksetup -getwebproxy "$svc"
    echo "MTU:";        networksetup -getMTU "$svc" 2>/dev/null
    echo
  } >> "$N/service-details.txt" 2>> "$LOG"
done
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
if [ -n "$WIFI_DEV" ]; then
  run "$N/wifi-preferred-networks.txt" networksetup -listpreferredwirelessnetworks "$WIFI_DEV"
  note "Wi-Fi 名稱已記錄;Wi-Fi 密碼不會備份(由 iCloud 鑰匙圈或手動輸入)"
fi
run "$N/ifconfig.txt" ifconfig
run "$N/scutil-dns.txt" scutil --dns
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if [ -x "$FW" ]; then
  {
    echo "## 防火牆總開關";  "$FW" --getglobalstate
    echo "## 隱身模式";      "$FW" --getstealthmode
    echo "## 允許的 App";    "$FW" --listapps
  } > "$N/firewall.txt" 2>> "$LOG"
fi
[ -f /etc/hosts ] && cp /etc/hosts "$N/hosts" 2>> "$LOG"
command -v tailscale > /dev/null 2>&1 && run "$N/tailscale-status.txt" tailscale status

# -----------------------------------------------------------------------------
say "7/12 顯示器設定(解析度、排列、更新率)"
D="$OUT/display"
run "$D/displays.txt" system_profiler SPDisplaysDataType
run "$D/graphics.json" system_profiler -json SPDisplaysDataType
if command -v displayplacer > /dev/null 2>&1; then
  run "$D/displayplacer-list.txt" displayplacer list
  # 最後一行就是可直接還原排列的指令
  grep '^displayplacer ' "$D/displayplacer-list.txt" | tail -1 > "$D/displayplacer-restore-command.txt"
  note "已存 displayplacer 還原指令"
else
  note "未安裝 displayplacer(可用 brew install displayplacer 取得精確還原指令),已改存系統資訊"
fi
export_domain com.apple.windowserver.displays "$D" 2>/dev/null
cp -R /Library/Preferences/com.apple.windowserver.displays.plist "$D/" 2>/dev/null

# -----------------------------------------------------------------------------
say "8/12 電源與睡眠(串流主機通常需要不睡眠)"
run "$OUT/power/pmset-custom.txt"   pmset -g custom
run "$OUT/power/pmset-current.txt"  pmset -g
run "$OUT/power/pmset-schedule.txt" pmset -g sched
{
  echo "## 共享服務狀態(螢幕共享 / 遠端登入 / 檔案共享)"
  launchctl print-disabled system 2>/dev/null | grep -iE 'screensharing|ssh|smbd|AppleFileServer'
} > "$OUT/power/sharing-services.txt" 2>> "$LOG"

# -----------------------------------------------------------------------------
say "9/12 開機啟動項目"
ST="$OUT/startup"
osascript -e 'tell application "System Events" to get the name of every login item' \
  > "$ST/login-items.txt" 2>> "$LOG" || note "無法讀取登入項目(請在「系統設定 > 一般 > 登入項目」截圖)"
if [ -d "$HOME/Library/LaunchAgents" ]; then
  mkdir -p "$ST/user-LaunchAgents"
  cp -R "$HOME/Library/LaunchAgents/." "$ST/user-LaunchAgents/" 2>> "$LOG"
fi
{
  echo "## /Library/LaunchAgents";  ls -1 /Library/LaunchAgents 2>/dev/null
  echo; echo "## /Library/LaunchDaemons"; ls -1 /Library/LaunchDaemons 2>/dev/null
} > "$ST/system-launch-items.txt"
run "$ST/launchctl-user-list.txt" launchctl list

# -----------------------------------------------------------------------------
say "10/12 隱私權限(輔助使用、螢幕錄製、麥克風等)"
PM="$OUT/permissions"
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if sqlite3 "$TCC_DB" "select 1;" > /dev/null 2>&1; then
  sqlite3 -header -separator $'\t' "$TCC_DB" \
    "select service, client, auth_value from access order by service, client;" \
    > "$PM/tcc-user.tsv" 2>> "$LOG"
  sqlite3 -header -separator $'\t' /Library/Application\ Support/com.apple.TCC/TCC.db \
    "select service, client, auth_value from access order by service, client;" \
    > "$PM/tcc-system.tsv" 2>/dev/null
  note "已讀取權限清單(auth_value 2 = 允許,0 = 拒絕)"
else
  note "終端機沒有「完整磁碟取用權限」,無法讀取權限資料庫。"
  note "→ 可到「系統設定 > 隱私權與安全性」把各權限頁面截圖存到隨身硬碟,或授權後重跑。"
  echo "未能讀取 TCC.db,請參考 README 的手動截圖步驟" > "$PM/NOT-READ.txt"
fi

# -----------------------------------------------------------------------------
say "11/12 Shell 設定檔、字型、音訊裝置"
DF="$OUT/dotfiles"
for f in .zshrc .zprofile .zshenv .bashrc .bash_profile .profile .gitconfig .gitignore_global .vimrc .tmux.conf; do
  [ -f "$HOME/$f" ] && cp "$HOME/$f" "$DF/" 2>> "$LOG"
done
# SSH:只備份 config 與 known_hosts,不備份私鑰
if [ -d "$HOME/.ssh" ]; then
  mkdir -p "$DF/ssh"
  [ -f "$HOME/.ssh/config" ] && cp "$HOME/.ssh/config" "$DF/ssh/"
  [ -f "$HOME/.ssh/known_hosts" ] && cp "$HOME/.ssh/known_hosts" "$DF/ssh/"
  ls -1 "$HOME/.ssh" > "$DF/ssh/file-list.txt"
  note "SSH 私鑰未備份(若需要請另外用密碼管理器或加密方式保存)"
fi
if [ -d "$HOME/Library/Fonts" ] && [ -n "$(ls -A "$HOME/Library/Fonts" 2>/dev/null)" ]; then
  cp -R "$HOME/Library/Fonts/." "$OUT/fonts/" 2>> "$LOG"
fi
run "$OUT/audio/audio-devices.txt" system_profiler SPAudioDataType
export_domain com.apple.audio.AudioMIDISetup "$OUT/audio" 2>/dev/null

# -----------------------------------------------------------------------------
say "12/12 收尾:複製復原包、安全檢查、產生清單"
for f in README.md restore.md restore.sh backup.sh MANUAL-SECRETS.md; do
  [ -f "$KIT_DIR/$f" ] && cp "$KIT_DIR/$f" "$OUT/kit/"
done
cp "$KIT_DIR/restore.md" "$OUT/restore.md" 2>/dev/null
cp "$KIT_DIR/MANUAL-SECRETS.md" "$OUT/MANUAL-SECRETS.md" 2>/dev/null
chmod +x "$OUT/kit/"*.sh 2>/dev/null

# 安全檢查:掃描是否不小心帶到私鑰或明碼
grep -rIlE -- '-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----' "$OUT" 2>/dev/null \
  | grep -v '/kit/' > "$OUT/SECURITY-WARNINGS.txt"
if [ -s "$OUT/SECURITY-WARNINGS.txt" ]; then
  echo "!!! 發現疑似私鑰檔案,已列在 SECURITY-WARNINGS.txt,請確認後刪除 !!!" | tee -a "$LOG"
else
  echo "未發現私鑰。" > "$OUT/SECURITY-WARNINGS.txt"
fi

(cd "$OUT" && find . -type f ! -name MANIFEST.txt | sort > MANIFEST.txt)

say "完成!"
echo "備份位置:$OUT"
echo "檔案數:$(wc -l < "$OUT/MANIFEST.txt" | tr -d ' ')   大小:$(du -sh "$OUT" | cut -f1)"
echo "失敗或略過的項目請看:$LOG"
echo
echo "下一步:照 README.md 的「重置前手動確認清單」逐項打勾,再重置 Mac。"
