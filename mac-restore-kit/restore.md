# 給 AI 的 Mac 復原指引(restore.md)

你(AI 助理)正在協助使用者,在**剛重置的 Mac** 上,用隨身硬碟上的備份復原串流軟體(主要是 **Parsec**)和所有相關設定。請**依序**執行,每一大步完成後向使用者回報,再進下一步。

## 0. 安全規則(務必遵守)

1. **不要要求使用者把密碼、驗證碼、金鑰貼到對話裡。** 需要密碼的地方(`sudo`、App 登入)請使用者自己在終端機或 App 內輸入。
2. **覆蓋任何檔案前先備份現有檔案**(例如 `cp -R 原檔 ~/restore-safety-backup/`)。
3. **不要整包覆蓋 `~/Library/Preferences`**,也不要對 `NSGlobalDomain` 盲目 `defaults import`;若 macOS 主版本與備份時不同,只匯入使用者確認需要的網域。
4. 隱私權限(TCC)**不能也不要**用腳本修改 TCC.db(SIP 會阻擋,也可能弄壞系統),請引導使用者手動開啟。
5. 任何會改變系統層級的指令(`sudo`、安裝驅動/系統延伸功能)先向使用者說明再執行。
6. 遇到失敗不要硬繞過,記錄下來並告訴使用者。

## 1. 找到備份並了解環境

```bash
ls /Volumes/                          # 找到隨身硬碟
ls -d /Volumes/*/MacBackup-*          # 找到備份資料夾,若有多個用最新的
B=/Volumes/<隨身硬碟>/MacBackup-<日期>  # 之後都用 $B 代表
```

先讀以下檔案,整理成摘要回報給使用者:

| 檔案 | 要看什麼 |
|---|---|
| `$B/system/sw_vers.txt`、`hardware.txt`、`identity.txt` | 舊系統版本、型號、晶片(Apple Silicon / Intel)、電腦名稱 |
| `sw_vers`、`uname -m`(現在的系統) | 與備份比較版本與架構 |
| `$B/apps/app-versions.tsv` | 要重裝的 App 清單 |
| `$B/streaming/`(整個資料夾) | 有哪些串流軟體設定 |
| `$B/streaming/related-components.txt` | 虛擬音效卡、驅動、系統延伸功能 |
| `$B/backup.log` | 備份時哪些項目失敗(那些資訊可能缺) |
| `$B/SECURITY-WARNINGS.txt` | 確認沒有私鑰 |
| `$B/` 下的截圖(如果有) | 使用者手動截的權限 / Parsec 設定畫面 |

回報範例:「備份來自 MacBook Pro M2、macOS 15.x;現在是 macOS 15.y。找到 Parsec 設定、Brewfile(N 個套件)、BlackHole 音訊驅動、displayplacer 指令。備份時沒有讀到權限清單。」

## 2. 基本系統

1. 電腦名稱(Parsec 主機列表顯示的名稱):讀 `$B/system/identity.txt`,經使用者同意後
   `sudo scutil --set ComputerName "<值>"`,`LocalHostName`、`HostName` 同理(HostName 若為空則略過)。
2. 確認已安裝 Xcode Command Line Tools:`xcode-select -p || xcode-select --install`。

## 3. 安裝軟體

1. 沒有 Homebrew 就安裝(官方指令,使用者需輸入密碼):
   `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
   Apple Silicon 安裝後執行 `eval "$(/opt/homebrew/bin/brew shellenv)"`,並確認 `~/.zprofile` 有該行。
2. 給使用者看 `$B/homebrew/Brewfile`,同意後 `brew bundle --file="$B/homebrew/Brewfile"`。失敗的項目列出來。
3. 若 Brewfile 沒有包含 Parsec:`brew install --cask parsec`,或請使用者從 https://parsec.app/downloads 下載。
4. 比對 `$B/apps/app-versions.tsv` 與現在的 `/Applications`,列出**還沒裝回來的 App**給使用者決定。App Store 的 App 若有 `mas-list.txt`,可用 `mas install <id>`(需先登入 App Store)。
5. 若 `related-components.txt` 有 **BlackHole** 等虛擬音效卡、**BetterDisplay** 等虛擬螢幕工具,一併安裝(多半有 brew cask:`blackhole-2ch`、`betterdisplay`)。安裝驅動時提醒使用者到「系統設定 > 隱私權與安全性」底部按「允許」,可能需重開機。

## 4. 還原 Parsec 設定

1. 確認 Parsec **已安裝並完全結束**:`pgrep -il parsec` 應無輸出(有的話請使用者從選單列 Quit)。
2. 備份現有並還原:
   ```bash
   [ -d ~/.parsec ] && cp -R ~/.parsec ~/restore-safety-backup-parsec
   mkdir -p ~/.parsec
   rsync -a "$B/streaming/parsec-home/" ~/.parsec/
   ```
3. 若有 `$B/streaming/parsec-appsupport/`,同樣還原到 `~/Library/Application Support/Parsec/`。
4. 若 `$B/streaming/plists/` 有 `tv.parsec.www.plist` 之類的檔案:`defaults import <網域> <檔案>`。
5. 打開 Parsec,請使用者**自行登入**(帳號密碼與 2FA 由使用者輸入)。
6. 讓使用者看 Parsec **Settings > Host**,比對 `~/.parsec/config.*` 或截圖,確認 Hosting 開啟、解析度、頻寬、編碼器等與以前相同。

## 5. 權限(使用者手動)

讀 `$B/permissions/tcc-user.tsv`(若存在),整理出「哪些 App 在哪個權限是允許(auth_value=2)」。
`kTCCServiceScreenCapture`=螢幕錄製、`kTCCServiceAccessibility`=輔助使用、`kTCCServiceMicrophone`=麥克風、`kTCCServiceListenEvent`=輸入監控、`kTCCServiceSystemPolicyAllFiles`=完整磁碟取用權限。
沒有該檔就用使用者的截圖。

可以幫使用者直接打開對應頁面:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
```

Parsec 至少要:**螢幕錄製 + 輔助使用**(主機端)。開啟後請使用者完全結束再重開 Parsec。

## 6. 其他串流相關軟體

`$B/streaming/` 裡每個子資料夾對應一個 App,有的才還原(先結束該 App、先備份現有):

| 備份資料夾 | 還原到 |
|---|---|
| `moonlight/` | `~/Library/Application Support/Moonlight Game Streaming Project/` |
| `sunshine/` | `~/.config/sunshine/`(配對憑證未備份,需重新配對) |
| `obs-studio/` | `~/Library/Application Support/obs-studio/` |
| `steam-config/` | `~/Library/Application Support/Steam/config/` |
| `betterdisplay/` | `~/Library/Application Support/BetterDisplay/` |
| `karabiner/` | `~/.config/karabiner/` |

`$B/streaming/plists/*.plist` 逐一問使用者後 `defaults import <檔名去掉 .plist> <檔案>`。

## 7. 顯示器

- 有 `$B/display/displayplacer-restore-command.txt`:確認螢幕已接上相同設備,`brew install displayplacer` 後執行檔案中的指令。螢幕 ID 若不同(重置後可能變),先 `displayplacer list` 比對,把舊 ID 換成新的再執行。
- 沒有:對照 `$B/display/displays.txt` 的解析度/更新率,引導使用者在「系統設定 > 顯示器」手動調整。

## 8. 網路

對照 `$B/network/service-details.txt`:
- 若某介面是手動 IP(Manual Configuration),用 `sudo networksetup -setmanual "<服務>" <IP> <子網路遮罩> <路由器>` 還原。
- 自訂 DNS:`sudo networksetup -setdnsservers "<服務>" <DNS1> <DNS2>`。
- 服務順序:參考 `service-order.txt`,`sudo networksetup -ordernetworkservices ...`。
- 防火牆:`firewall.txt` 顯示原本開啟則 `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on`;Parsec 第一次啟動跳出提示時選「允許」。
- 自訂 `hosts`:和 `/etc/hosts` 比對,只把使用者自己加的行補回(需 sudo)。
- Wi-Fi 密碼由使用者輸入或來自 iCloud 鑰匙圈。
- Tailscale / ZeroTier:若備份中有,重新安裝並請使用者登入。

## 9. 電源與睡眠(串流主機很重要)

讀 `$B/power/pmset-custom.txt`,把「AC Power」區段的值逐一還原,例如:

```bash
sudo pmset -c sleep 0 displaysleep 10 disksleep 0 womp 1 powernap 0 autorestart 1
```

(數值以備份檔為準,上面只是範例。)若是筆電,電池(`-b`)設定也照備份還原。

## 10. 系統偏好、Shell、字型、開機啟動

1. `$B/prefs/*.plist`:列出清單,使用者勾選要的再 `defaults import`;完成後 `killall Dock Finder SystemUIServer`。
2. `$B/dotfiles/`:先備份現有,再複製 `.zshrc` 等回家目錄;`ssh/config`、`known_hosts` 放回 `~/.ssh/` 並 `chmod 600`。
3. `$B/fonts/` → `~/Library/Fonts/`。
4. `$B/startup/login-items.txt`:把仍存在的 App 加回登入項目
   `osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Parsec.app", hidden:false}'`
   **Parsec 主機通常需要開機自動啟動**,務必確認。
5. `$B/startup/user-LaunchAgents/`:對應程式已安裝的才複製回 `~/Library/LaunchAgents/` 並 `launchctl bootstrap gui/$(id -u) <檔案>`。

也可以直接讓使用者執行半自動腳本處理第 2~10 步:
`"$B/kit/restore.sh" "$B"`

## 11. 驗收

逐項確認並回報結果(✓ / ✗ 與原因):

- [ ] Parsec 已登入,Settings > Host 顯示 Hosting Enabled
- [ ] 從另一台裝置連進這台 Mac:**看得到畫面、能操控滑鼠鍵盤、有聲音**
- [ ] 重開機後 Parsec 自動啟動,且不需手動登入
- [ ] 接電源時主機不會進入睡眠(`pmset -g` 確認 `sleep 0`)
- [ ] 顯示器解析度/排列與以前相同
- [ ] Brewfile 中的套件都已安裝(`brew bundle check --file="$B/homebrew/Brewfile"`)
- [ ] `MANUAL-SECRETS.md` 中使用者用得到的項目都已重新登入

最後列出:已完成項目、失敗/略過項目及原因、使用者還需要手動做的事。
