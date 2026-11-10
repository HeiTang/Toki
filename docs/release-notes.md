## Toki 1.5.3

正式套件改用 macOS SDK 27.0 建置，讓支援新版原生外觀的 macOS 顯示新版工具列和按鈕樣式。

### 本次更新

- **原生外觀**：視窗工具列和按鈕會依 macOS 版本套用原生樣式，保留 v1.5.2 的版面與操作方式。
- **升級方式**：使用 1.5.1 或 1.5.2，可從「Toki → 檢查更新」安裝這一版。使用 1.5.0 或更舊版本請先手動安裝。

### 版本與限制

- 版本 **1.5.3／build 29**。
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
