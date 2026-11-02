# Mac 重置復原包(串流軟體 + 全部設定)

這個資料夾放進隨身硬碟,就能在 Mac 重置前把設定備份起來,重置後再交給 AI(或自己)照著復原。

| 檔案 | 用途 |
|---|---|
| `backup.sh` | **重置前**執行,一鍵把設定備份到隨身硬碟 |
| `restore.sh` | **重置後**執行,每一步問你 y/N 再還原 |
| `restore.md` | **給 AI 看的**逐步復原指引(直接把這份交給 AI) |
| `MANUAL-SECRETS.md` | 不會被備份、需要你手動輸入的密碼/帳號清單 |

> 安全原則:腳本**不會**備份任何密碼、金鑰、登入權杖。Parsec 重新開啟後需要重新登入。

---

## 一、重置前(在舊系統上做)

### 1. 把復原包放到隨身硬碟

把整個 `mac-restore-kit` 資料夾複製到隨身硬碟,例如 `/Volumes/MyUSB/mac-restore-kit`。
隨身硬碟建議格式化為 **APFS** 或 **Mac OS 擴充格式**(exFAT 也可以,但檔案權限會遺失)。

### 2.(建議)給終端機「完整磁碟取用權限」

這樣腳本才能讀出「哪些 App 有輔助使用 / 螢幕錄製 / 麥克風權限」。

「系統設定 > 隱私權與安全性 > 完整磁碟取用權限」→ 按 `+` → 加入「終端機」→ 重開終端機。

### 3.(建議)安裝 displayplacer,才能精確還原螢幕解析度與排列

```bash
brew install displayplacer
```

### 4. 執行備份

打開「終端機」,輸入(把 `MyUSB` 換成你的隨身硬碟名稱):

```bash
cd /Volumes/MyUSB/mac-restore-kit
chmod +x backup.sh restore.sh
./backup.sh /Volumes/MyUSB
```

完成後隨身硬碟會多一個 `MacBackup-日期時間/` 資料夾。打開確認:

- `system/sw_vers.txt` 有 macOS 版本
- `streaming/parsec-home/` 有 Parsec 的 `config.txt` 或 `config.json`
- `homebrew/Brewfile` 存在(若你有用 Homebrew)
- `SECURITY-WARNINGS.txt` 顯示「未發現私鑰」

### 5. 重置前手動確認清單

- [ ] 截圖「系統設定 > 隱私權與安全性」中 **螢幕錄製、輔助使用、麥克風、輸入監控** 四個頁面,存到隨身硬碟(若第 2 步沒做,這步必做)
- [ ] 截圖「系統設定 > 一般 > 登入項目」
- [ ] 截圖 Parsec 的 **Settings > Host** 與 **Settings > Network** 頁面(解析度、編碼器、頻寬、連接埠等)
- [ ] 確認你記得 **Parsec 帳號密碼**,並能收到兩步驟驗證碼(或已保存備用碼)
- [ ] 確認 Apple ID 密碼、Wi-Fi 密碼可以取得(或存在 iCloud 鑰匙圈)
- [ ] 把 `MANUAL-SECRETS.md` 的每一項都確認「我知道去哪裡找」
- [ ] 其他個人檔案(文件、照片、遊戲存檔)另外備份 — 本腳本只備份**設定**
- [ ] 最後再到「系統設定 > 一般 > 移轉或重置 > 清除所有內容和設定」

---

## 二、重置後(在新系統上做)

### 方式 A:交給 AI

把 `MacBackup-日期時間/restore.md` 交給 AI(例如 Claude Code 在這台 Mac 上執行),說:

> 請依照 restore.md 的步驟,用 /Volumes/MyUSB/MacBackup-XXXX 的備份復原我的串流軟體與所有設定。

### 方式 B:自己跑腳本

```bash
/Volumes/MyUSB/MacBackup-XXXX/kit/restore.sh /Volumes/MyUSB/MacBackup-XXXX
```

每一步都會先問,按 Enter 就略過。最後會列出需要你手動開的權限。

---

## 備份內容一覽

| 資料夾 | 內容 |
|---|---|
| `system/` | Mac 型號、晶片、macOS 版本、電腦名稱 |
| `apps/` | 已安裝 App、版本、Bundle ID、App Store 清單 |
| `homebrew/` | `Brewfile`(所有 brew 套件與 cask App)、services |
| `streaming/` | Parsec(`~/.parsec`)設定,以及有安裝時的 Moonlight、Sunshine、OBS、Steam、BetterDisplay、Karabiner 設定、串流相關 plist、虛擬音效卡/驅動清單 |
| `prefs/` | Dock、Finder、鍵盤、觸控板、快捷鍵、輸入法等系統偏好 |
| `network/` | 網路服務、IP、DNS、Proxy、Wi-Fi 名稱、防火牆、hosts |
| `display/` | 螢幕資訊、displayplacer 還原指令 |
| `power/` | 睡眠/喚醒設定(pmset)、共享服務狀態 |
| `startup/` | 登入項目、LaunchAgents |
| `permissions/` | 隱私權限清單(需要完整磁碟取用權限) |
| `dotfiles/` | `.zshrc`、`.gitconfig`、`ssh/config`(**不含私鑰**) |
| `fonts/`、`audio/` | 自行安裝的字型、音訊裝置設定 |
| `kit/` | 復原包本身 |
| `MANIFEST.txt`、`backup.log` | 檔案清單、執行紀錄(失敗項目會記在 log) |
