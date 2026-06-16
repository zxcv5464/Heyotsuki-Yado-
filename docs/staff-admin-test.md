# 湯娘管理測試清單

## 權限

- [ ] `owner` 可以進入 `admin/staff.html`，看見全部湯娘與編輯表單。
- [ ] `admin` 可以進入 `admin/staff.html`，看見全部湯娘與編輯表單。
- [ ] `staff` 進入時顯示「此帳號沒有湯娘管理權限」。
- [ ] `staff` 看不到新增、編輯、上傳與顯示切換介面。
- [ ] 使用 `staff` session 直接呼叫 Database 或 Storage 寫入時，RLS 仍會拒絕。

## 資料管理

- [ ] 新增一位測試湯娘，不選圖片，只手動填入 `image_url`。
- [ ] 新增資料未填 `sort_order` 時，自動使用目前最大值加 10。
- [ ] 編輯名稱、副標題、湯語、職位、圖片 URL、顯示狀態與排序後可成功儲存。
- [ ] 儲存成功後顯示成功訊息並重新載入列表。
- [ ] 模擬 RLS 或網路錯誤時顯示失敗訊息。
- [ ] 後台列表包含 `is_visible = false` 的資料。
- [ ] 列表依 `sort_order` 由小到大排列。
- [ ] 關閉 `is_visible` 後，前台 `staff.html` 不顯示該湯娘，但後台仍看得到並標示「已隱藏」。
- [ ] 調整 `sort_order` 後，前台排序跟著改變。
- [ ] 畫面沒有永久刪除按鈕。

## 圖片上傳

- [ ] 新增一位測試湯娘，使用圖片上傳並成功儲存。
- [ ] 選擇圖片後先顯示本地預覽，尚未上傳前不改動原本 `image_url`。
- [ ] JPG/JPEG 上傳前轉成 WebP。
- [ ] PNG 上傳前轉成 WebP，透明背景可保留。
- [ ] WebP 仍重新縮放及壓縮成 WebP。
- [ ] GIF 僅取第一幀並轉成 WebP，不保留動畫。
- [ ] 大圖只縮小、不放大，尺寸不超過 600 × 800。
- [ ] 輸出 quality 為 0.76。
- [ ] 上傳路徑符合 `staff/{yyyyMMdd-HHmmss}-{slug}.webp`。
- [ ] 無法產生英文 slug 時使用 `staff`。
- [ ] 同名檔案衝突時自動更換 timestamp，不覆蓋既有圖片。
- [ ] 上傳使用 `contentType: image/webp`、`cacheControl: 31536000` 與 `upsert: false`。
- [ ] 新圖片回應標頭包含 `max-age=31536000` 或 `public, max-age=31536000`。
- [ ] 上傳成功後，`image_url` 自動填入 `heyotsuki-images` 的 public URL。
- [ ] 上傳失敗時顯示錯誤，且不清空原本 `image_url`。
- [ ] 更換圖片不會自動刪除舊 Storage object。

## 前台

- [ ] 儲存後 `staff.html` 顯示新湯娘。
- [ ] `image_url` 是 Supabase Storage public URL。
- [ ] Network 面板可看到圖片由 `supabase.co/storage` 載入。
- [ ] 湯語中的 textarea 換行會顯示為換行。
- [ ] 既有 `<br>` 湯語仍能正常換行。
- [ ] 湯語中的其他 HTML 標籤會以純文字顯示，不會被執行。
- [ ] 卡片圖片裁切、翻牌效果與原本視覺保持一致。

## 手機版

- [ ] 手機可新增、編輯、選圖、上傳與儲存。
- [ ] 湯娘列表沒有水平溢位。
- [ ] 編輯與顯示/隱藏按鈕可正常點擊。
