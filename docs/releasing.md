# 建置與發布

## 本機驗證

```sh
./build.command
./release.command
```

需要 Apple Silicon、macOS 13 以上、Xcode Command Line Tools 及首次建置時的網路。
ExifTool 13.55 從官方 CPAN 來源下載，固定 SHA-256，快取於 `.build/`。
不使用 Homebrew 的修改版本。第三方授權位於 `ThirdParty/ExifTool/`，並隨 App 提供。

`build.command` 在 App bundle 內執行全部自測，檢查確實使用內附 ExifTool。
`release.command` 驗證 metadata、arm64、圖示、ExifTool 與簽章，產生 DMG 與 ZIP；
實際掛載 DMG，確認 Applications 捷徑，複製 App 後重跑自測，再解壓 ZIP 比對完整內容。
下載檔及 `SHA256SUMS.txt` 位於 `dist/`，不納入 Git。

## 自動發布

1. 更新 `Resources/Info.plist` 的 `CFBundleShortVersionString` 與遞增 `CFBundleVersion`。
2. 更新 `docs/release-notes.md`，完成本機驗證並提交程式碼。
3. 在準備發布的 commit 建立與版本一致的標籤，例如 `v1.4.1`，推送該標籤。

[Release workflow](../.github/workflows/release.yml) 會檢查標籤與 App 版本相符，
建置、測試、封裝，再發布 GitHub Release，附上 DMG、ZIP、SHA-256。
一般使用者從 Releases 下載，不必登入 Actions，也沒有 CI artifact 的 14 天期限。
README 的下載網址預定為 `HeiTang/Toki`；若採用其他儲存庫名稱，需同步更新 README 與安裝說明。

重跑已發布的版本時，`gh release create` 會拒絕覆蓋既有 Release。
修正後請遞增版本並建立新標籤。Git 標籤與 Release 應保留，不以相同版本替換產物。

## Developer ID 簽章與 Apple 公證

目前未設定憑證時，流程會明確標示 **ad-hoc 簽章、尚未公證**，仍會發布可下載的版本。
Apple Development／Apple Distribution 憑證不能取代 Developer ID Application。

正式公證需在儲存庫 Actions secrets 設定以下五項：

| Secret | 內容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 含私鑰的 Developer ID Application `.p12`，經 Base64 編碼 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 匯出密碼（此流程要求非空） |
| `APPLE_ID` | 開發者 Apple ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_PASSWORD` | Apple ID 的 app-specific password |

有提供任何一項時，五項必須完整；缺漏會直接失敗。
憑證只在 tag release job 匯入暫存 keychain，結束後刪除；PR 不會使用發布憑證。
流程自動使用 hardened runtime、timestamp，提交 App 與 DMG 公證、staple ticket，
並用 `spctl` 驗證。Apple 公證失敗時不會發布 Release。

若在本機完成相同流程，先在 Keychain 設定 Developer ID 與 `notarytool` profile，再執行（自訂 keychain 時另設 `NOTARY_KEYCHAIN` 為其路徑）：

```sh
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export NOTARY_PROFILE='your-notarytool-profile'
./build.command
./release.command
```

未設定憑證時，`codesign --verify` 只能證明封裝完整性，不能代表 Apple 公證或 Gatekeeper 接受。
