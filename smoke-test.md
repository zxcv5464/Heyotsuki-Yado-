# Supabase Phase 1 Smoke Test

測試前請使用瀏覽器開發者工具的 Network 與 Console 面板，確認資料來源與錯誤狀態。每次修改資料後重新整理頁面。

## A. 未設定 Supabase

先確認 `js/supabase-client.js` 保持 placeholder。

- [ ] 開啟 `staff.html`，確認正常顯示本地湯娘資料。
- [ ] 開啟 `menu.html`，確認正常顯示本地湯宿菜單。
- [ ] 開啟 `menu2.html`，確認正常顯示本地喫茶菜單。
- [ ] 確認三個頁面沒有因 Supabase 未設定而出現空白或 JavaScript 錯誤。

## B. 完成 Supabase 設定

先執行 `schema.sql`、`seed.sql`，並在 `js/supabase-client.js` 填入 Project URL 與 publishable key。

- [ ] 開啟 `staff.html`，確認 Network 面板有讀取 `staff_members`，且頁面顯示資料庫內容。
- [ ] 開啟 `menu.html`，確認讀取 `menus` 中的 `menu`、其 `menu_sections` 與 `menu_items`。
- [ ] 開啟 `menu2.html`，確認讀取 `menus` 中的 `menu2`、其 `menu_sections` 與 `menu_items`。
- [ ] 確認 Console 沒有 RLS、HTTP 或 JavaScript 錯誤。

## C. 可見性測試

測試前記錄被修改資料，測試後恢復原值。

### 湯娘

1. 在 `staff_members` 選一筆目前顯示的資料。
2. 將 `is_visible` 改為 `false`。
3. 重新整理 `staff.html`。

- [ ] 該湯娘不再顯示。
- [ ] 其他湯娘仍正常顯示。
- [ ] 將 `is_visible` 恢復為 `true` 後重新顯示。

### 菜單品項

1. 在 `menu_items` 選一筆目前顯示的資料。
2. 將 `is_visible` 改為 `false`。
3. 重新整理對應的 `menu.html` 或 `menu2.html`。

- [ ] 該品項不再顯示。
- [ ] 同區段其他品項仍正常顯示。
- [ ] 將 `is_visible` 恢復為 `true` 後重新顯示。

## D. 排序測試

測試前記錄原本的 `sort_order`，測試後恢復。

- [ ] 修改兩筆 `staff_members.sort_order`，重新整理後湯娘排序跟著改變。
- [ ] 修改兩筆同菜單的 `menu_sections.sort_order`，重新整理後區段排序跟著改變。
- [ ] 修改兩筆同區段的 `menu_items.sort_order`，重新整理後品項排序跟著改變。

## E. Fallback 測試

完成 Supabase 設定後，暫時使用錯誤 Project URL，或在瀏覽器開發者工具中阻擋 Supabase request。

- [ ] `staff.html` 自動回退並顯示本地 `js/data-staff.js`。
- [ ] `menu.html` 自動回退並顯示本地 `js/data-menu.js`。
- [ ] `menu2.html` 自動回退並顯示本地 `js/data-menu2.js`。
- [ ] 恢復正確設定後，三頁重新從 Supabase 讀取。

## F. RLS 基本檢查

- [ ] 未登入訪客可以讀取 `site_settings`。
- [ ] 未登入訪客可以讀取 `is_visible = true` 的 `staff_members`、`menus`、`menu_sections` 與 `menu_items`。
- [ ] 未登入訪客查不到任何 `is_visible = false` 的資料。
- [ ] 有效且啟用的 `owner` 登入後，可以查到上述資料表中 `is_visible = false` 的資料。
- [ ] 有效且啟用的 `admin` 登入後，可以查到上述資料表中 `is_visible = false` 的資料。
- [ ] 有效且啟用的 `owner` 或 `admin` 可以新增、修改與刪除內容。
- [ ] `staff` 登入後只能讀取公開內容，不能新增、修改或刪除內容。
- [ ] 將 `owner`、`admin` 或 `staff` 的 `is_active` 改為 `false` 後，不再取得其管理權限。
- [ ] `site_settings` 可由前台讀取。
- [ ] 前端沒有 `sb_secret_` 或 legacy `service_role` key。
