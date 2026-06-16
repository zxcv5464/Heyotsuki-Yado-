# 遊戲卡管理測試清單

## 套用順序

1. 先確認既有 `supabase/schema.sql` 已套用。
2. 執行 `supabase/migrations/20260615090000_game_staff_card_settings.sql`。
3. 若曾在修正前套用 Phase 1，執行 `supabase/migrations/20260615100000_allow_game_card_auto_assign_trusted_roles.sql`。
4. 若已遇到 auto-assign `staff_id is ambiguous`，執行 `supabase/migrations/20260615103000_fix_game_card_auto_assign_conflict.sql`。
5. 重新執行 `supabase/storage.sql`，開放 `game-cards/` 管理寫入。
6. 依 `supabase/game-card-smoke-test.sql` 驗證資料庫結果。
7. 部署後台靜態檔案。

## 權限

- [ ] `owner` 與 `admin` 可開啟 `admin/game-cards.html`。
- [ ] `owner` 與 `admin` 可讀寫遊戲卡設定及執行自動分配。
- [ ] `staff` 看到無權限訊息，不能讀寫設定表或執行自動分配。
- [ ] anon 不能直接查詢 `game_staff_card_settings`。
- [ ] anon 與 authenticated 可執行 `get_active_game_staff_cards()`。
- [ ] Dashboard SQL Editor 與 API `service_role` 可執行自動分配維護操作。
- [ ] 前端檔案不含 service role、資料庫密碼或其他私密金鑰。

## 月份與季節

- [ ] 後台月份依序顯示一月・松月至十二月・雪月。
- [ ] 1–3 月固定為春、4–6 月為夏、7–9 月為秋、10–12 月為冬。
- [ ] 後台沒有可獨立編輯季節的欄位。
- [ ] 修改月份後，季節與卡片預覽立即同步。

## 卡池資格

- [ ] 顯示、啟用、設定完整且有有效圖片的員工出現在 active RPC。
- [ ] `is_visible = false` 後，不再出現在新卡池 RPC。
- [ ] 重新顯示後，原遊戲卡設定仍存在。
- [ ] `is_game_enabled = false` 後，不再出現在新卡池 RPC。
- [ ] 未建立設定的員工不出現在新卡池 RPC。
- [ ] 一般照片與專用卡面皆空時，不出現在新卡池 RPC。
- [ ] 專用卡面存在時優先於 `staff_members.image_url`。
- [ ] 專用卡面留空時沿用 `staff_members.image_url`。
- [ ] 正式啟用前，active RPC 回傳的每個圖片 URL 都能由獨立遊戲網域載入；相對路徑資料應改為 Storage public URL 或設定專用卡面。
- [ ] active RPC 失敗時沒有本地 `STAFF_DATA` 備援。

## 自動分配

- [ ] 自動分配只新增目前沒有設定列的員工。
- [ ] 既有月份、印記、標題、圖片與啟用狀態不被改寫。
- [ ] 優先選擇啟用卡數量最少的月份。
- [ ] 月份平手時依 1 到 12 月選擇。
- [ ] 再選擇啟用卡數量最少的印記。
- [ ] 印記平手時依 moon、bell、fan、knot 選擇。
- [ ] 分配結果永久寫入資料庫。
- [ ] 緊接著重跑時回傳 0 筆，資料保持不變。

## 後台介面

- [ ] 首頁與湯娘管理頁可進入遊戲卡管理。
- [ ] 湯娘列表顯示未設定、啟用或停用狀態。
- [ ] 快速入口會自動開啟指定湯娘編輯器。
- [ ] 未設定、停用、隱藏及名稱搜尋篩選正確。
- [ ] 摘要顯示總數、可進卡池數與未設定數。
- [ ] 月份與印記統計只計算目前啟用的設定。
- [ ] 卡片預覽使用專用圖片優先、一般照片 fallback。
- [ ] 卡面上傳至 `game-cards/{timestamp}-{slug}.webp`。
- [ ] 卡面等比例縮放至 600 × 800 以內，不裁切且小圖不放大。
- [ ] 卡面轉成 `image/webp`，quality 為 0.76，GIF 僅取第一幀。
- [ ] 卡面上傳使用 `cacheControl: 31536000`、`contentType: image/webp` 與 `upsert: false`。
- [ ] 新卡面回應標頭包含 `max-age=31536000` 或 `public, max-age=31536000`。
- [ ] 手機版無水平溢位，表單與操作按鈕可用。

## 既有 Staff CRUD 回歸

- [ ] 新增湯娘的欄位與預設排序維持原行為。
- [ ] 編輯名稱、圖片、顯示、預約與排序仍可成功。
- [ ] 一般照片仍上傳至 `staff/`，不會改用 `game-cards/`。
- [ ] 顯示／隱藏切換仍可成功。
- [ ] migration 尚未部署而遊戲設定查詢失敗時，既有 staff 列表與 CRUD 仍可使用。
- [ ] 預約、點餐、報表與 Discord 通知流程沒有被修改。

## 未來遊戲共用需求（本階段不實作）

- 回合數：`min(6, floor((active_card_count - 6 - player_count) / player_count))`，
  每位玩家預留一張牌作為動態補場容量。
- 26 張有效卡支援 4 人、每人 4 回合；22 張有效卡支援每人 3 回合。
- 斷線重連窗口為 10 分鐘。
- 遊戲狀態採版本化 JSONB snapshot、version、action ID、row lock 與交易式 RPC。
