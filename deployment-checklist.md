# GitHub Pages 部署檢查清單

## 部署檔案

- [ ] 確認 `.gitignore` 包含 `_image_backup/`。
- [ ] 確認 `_image_backup/originals` 未出現在 GitHub Pages 的部署內容中。
- [ ] 若 `_image_backup` 曾被 Git 追蹤，執行：

  ```bash
  git rm -r --cached _image_backup
  git commit -m "Remove image backup from deployment"
  ```

- [ ] 確認上述指令只移除 Git 追蹤，不刪除本機原始圖片。

## 頁面與資源

- [ ] 確認首頁 `index.html` 可正常開啟。
- [ ] 確認入場規範 `rules.html` 可正常開啟。
- [ ] 確認湯娘介紹 `staff.html` 可正常開啟。
- [ ] 確認菜單總覽 `menus.html` 可正常開啟。
- [ ] 確認湯宿菜單 `menu.html` 可正常開啟。
- [ ] 確認喫茶菜單 `menu2.html` 可正常開啟。
- [ ] 確認線上預約 `reservation.html` 可正常載入表單並送出測試資料。
- [ ] 確認已執行 `supabase/reservation-availability-migration.sql`。
- [ ] 確認預約日期只列出仍有可用時段的日期，切換日期後時段會同步更新。
- [ ] 確認第一位與第二位指定湯娘不可選擇同一人。
- [ ] 確認 `pending` / `confirmed` 的同日期同時段無法建立重複預約。
- [ ] 確認所有圖片皆能載入，且路徑指向 `assets/images/` 下的正式分類資料夾。
- [ ] 確認 HTML、CSS、JavaScript 未引用 `_image_backup` 或 `assets/images/originals`。

## 導覽與設定

- [ ] 確認每個頁面的手機底部導覽皆正常顯示與切換。
- [ ] 確認手機底部「菜單」連到 `menus.html`。
- [ ] 確認 `SITE_CONFIG.bookingUrl` 僅保留為站內預約表無法載入時的舊表單 fallback。
- [ ] 確認手機底部、footer 與桌機右側「預約」皆連到 `reservation.html`。
- [ ] 確認桌機版「菜單」下拉選單可用。
- [ ] 確認下拉選單包含「湯宿菜單」與「喫茶菜單」。
- [ ] 確認 `menus.html` 顯示兩張菜單卡片。
- [ ] 確認首頁與規範頁的預約按鈕使用 `SITE_CONFIG.bookingUrl`。
- [ ] 確認湯娘頁的 Discord 招募按鈕使用 `SITE_CONFIG.discordUrl`。
- [ ] 確認 footer 的地址、營業日、營業時間、狀態與外部連結皆來自 `SITE_CONFIG`。

## 外部連結

- [ ] 確認所有 `target="_blank"` 的外部連結皆包含 `rel="noopener noreferrer"`。
- [ ] 確認預約表單、Threads 與 Discord 連結可正常開啟。
- [ ] 確認 `supabase/.temp/` 未被 Git 追蹤；此目錄是 Supabase CLI
      暫存連線資訊，不可部署或提交到 GitHub。

## Staff 圖片 fallback

- [ ] 若保留 `assets/images/staff/` 的本地圖片，Supabase 無法讀取時，前台仍可透過本地 fallback 正常顯示。
- [ ] 若未來要刪除 `assets/images/staff/`，必須先將 `js/data-staff.js` 與 `supabase/seed.sql` 的圖片路徑更新為 Supabase Storage public URL。
