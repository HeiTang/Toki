## Toki 1.5.1

Toki 現在可以在 App 內檢查、下載並安裝新版。

### 本次更新

- **App 內更新**：從「Toki → 檢查更新⋯」手動查看新版。選擇安裝後，Toki 會驗證更新包的簽章，再安裝並重新啟動。
- **背景檢查**：預設會定期檢查新版。若要自動下載及安裝，可在 Sparkle 更新視窗勾選對應選項。
- **從舊版升級**：目前使用 1.5.0 或更舊版本，請先手動安裝這一版，之後就能在 App 內更新。

### 版本與限制

- 版本 **1.5.1／build 27**。
- 只修改檔名，不改寫媒體內容；復原紀錄不是媒體備份。
- XMP／AAE 與 Live Photo 配對不會連動更名。

## 下載與安裝

適用於 **Apple Silicon（M1 或更新）／macOS 13 以上**。

1. 下載下方的 **Toki-macos-arm64.dmg**。
2. 開啟 DMG，將 **Toki.app** 拖到 **Applications**。
3. 從「應用程式」開啟 Toki。

若 macOS 顯示「無法驗證開發者」，請先確認檔案來自 Toki 的 GitHub Releases，再依 README 的安裝說明操作。

App 已內附 ExifTool，無須安裝 Homebrew。

也提供 ZIP；解壓後將 Toki.app 移至「應用程式」。`SHA256SUMS.txt` 可供校驗下載檔案。

> 「Source code」是開發用原始碼。一般使用者請下載 DMG 或 ZIP。
