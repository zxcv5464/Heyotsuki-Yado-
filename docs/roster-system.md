# 排班系統第一版

## 目的與範圍

排班系統讓員工填寫各班別的可上班狀態，管理者依此建立草稿、手動調整並發布正式班表。第一版不包含打卡、請假、換班、Discord 通知或薪資自動串接。

薪資公共池仍由薪資頁手動選人；未來可用已發布班表作為候選來源，但本版不會改變任何薪資分潤結果。

## 資料設計

- `roster_periods`：排班期間與狀態；管理畫面只呈現「開放填寫」與「關閉填寫」。資料庫會保留既有 `draft`、`open`、`published`、`locked` 值以維持歷史資料相容性。
- `roster_shift_slots`：期間內各日期／名稱／開始與結束時間的班別，不限制兩班制。
- `roster_roles`：可自訂職位及每班最少／最多人數。
- `roster_period_role_requirements`：建立期間時的職位需求快照；日後改職位不會改舊班表。
- `roster_availability`：每位員工對每班的 `unselected`、`available`、`unavailable`、`standby`。
- `roster_assignments`：草稿或已發布的職位人員；`pending` 表示待定。

## 員工填寫流程

1. 登入後進入「排班管理」。
2. 在管理員開放的期間，填寫自己的可／否／備用／未選擇。
3. 儲存自己的狀態。發布後不能直接修改；請聯絡管理員處理。

員工只能寫入其 `admin_profiles.staff_id` 對應的 `staff_members`。未綁定員工的一般帳號不能提交 availability。

## 管理員流程

1. 建立期間與日期範圍；系統會自動命名為開始日期至結束日期，並預設產生每日兩班 `21:00-22:30`、`22:30-24:00`。新期間一律立即開放填寫。
2. 勾選要建立快照的職位需求，開放期間讓員工填寫。
   關閉填寫後，員工仍可查看自己已儲存的可上班狀態，但不可再修改；管理者需重新開放填寫後才能修改期間結構。
   新職位會自動排在最後，管理者可在職位清單以「上移／下移」手動調整順序；新期間快照會沿用此順序。
3. 以完整矩陣查看／代填狀態；可用欄位工具批量設為可、否、備用或清空。
4. 一鍵排班產生 draft，必要時啟用備用人員。
5. 手動新增、移除或調整職位人員；手動指定「否」的員工會收到警告。
6. 檢查待定職位後，班表會直接依目前排班結果顯示；停止填寫後，該期間會對員工隱藏。

## 一鍵排班規則

1. 僅使用 `available`；勾選「缺人時使用備用」才會使用 `standby`。
2. 不會使用 `unselected` 或 `unavailable`。
3. 同一班別同一員工不會被自動排入多個職位。
4. 平手時依期間內已排次數少、狀態、員工排序與姓名決定。
5. 手動 assignment 不會被一般重新產生覆蓋；選擇「清除既有草稿」才會全數重新產生。
6. 沒有足夠人員時建立 `pending`，前端顯示「待定」。

## 權限

- `roster.view`：查看已發布班表。
- `roster.submit`：在 open 期間填寫自己的可上班狀態。
- `roster.manage`：管理全部期間、班別、職位、矩陣與草稿。
- `roster.publish`：發布與鎖定班表。

Owner 擁有所有權限。管理員模板包含全部排班權限；櫃檯／營運包含查看與管理；一般員工包含查看與填寫。後端 RPC 與 RLS 都會檢查權限，並非只靠前端隱藏。

## 預覽、文字與 PNG

排班頁的「班表預覽」依日期收納，最新日期在上；每一天可獨立複製文字版或用瀏覽器 Canvas 下載 PNG。輸出不含管理按鈕，不使用外部圖片／Canvas CDN。

## 部署順序

1. 確認 `20260622040000_admin_permissions.sql` 與 `20260622050000_admin_permissions_hotfix_1.sql` 已套用。
2. 依序執行：
   - `supabase/migrations/20260622060000_roster_system_v1.sql`
   - `supabase/migrations/20260622061000_roster_period_workflow_hotfix.sql`
   - `supabase/migrations/20260622062000_roster_period_and_role_usability_hotfix.sql`
   - `supabase/migrations/20260622063000_roster_open_submission_status_hotfix.sql`
   - `supabase/migrations/20260622064000_roster_closed_period_readonly_visibility.sql`
   - `supabase/migrations/20260622065000_roster_closed_period_structure_guard.sql`
   - `supabase/migrations/20260622066000_roster_role_manual_ordering.sql`
3. 部署 `admin/roster.html`、`js/admin-roster.js`、`js/admin-auth.js`、`admin/index.html` 與 `css/admin.css`。
4. 以 Owner 登入，確認首頁有排班入口、建立期間、填 availability、產生草稿與發布。

不需要 Storage policy、Edge Function、service role 或 Realtime 設定。

## Rollback

先將排班頁從網站部署中移除，匯出需要保存的 `roster_*` 資料，再執行 `20260622060000_roster_system_v1.rollback.sql`。這會移除排班資料表、函式、RLS policy 與 `roster.*` 權限，無法保留班表資料。

## 人工驗收清單

1. Owner 可建立期間、職位、班別，並開放／停止填寫。
2. 僅有 `roster.submit` 的綁定員工只能看自己的 availability，不能讀完整矩陣。
3. 無 `roster.publish` 的管理者不能發布。
4. `available` 可被自動排入；`standby` 僅在勾選後使用；否與未選擇不會自動排入。
5. 同一班別不會由一鍵排班重複使用同一員工。
6. 人數不足顯示待定。
7. 停止填寫後員工不可再自行修改；管理者仍可查看與調整草稿。
8. PNG 與文字輸出不包含後台按鈕。

## 已知限制

第一版不處理跨店、換班、請假、出勤與薪資自動串接。職位快照僅在建立期間時生成；若需不同職位配置，請在草稿期間重建該期間結構後再開放填寫。
