# 後台權限管理

後台以 `admin_profiles.role` 保留 owner／admin／staff 身分，但實際功能採 `admin_profile_permissions` 的權限 key 判斷。`owner` 只要帳號啟用便永遠擁有全部權限，避免權限資料異常時把最後管理者鎖在門外。

## Migration 與部署

先確認既有網站、訂單、預約、遊戲卡與薪資 migration 已套用，再執行：

1. `supabase/migrations/20260622040000_admin_permissions.sql`
2. `supabase/migrations/20260622050000_admin_permissions_hotfix_1.sql`
3. 部署 `supabase/functions/admin-create-staff-account` 與 `supabase/functions/admin-manage-staff-account`
4. 將 `admin/`、`js/` 與本文件的網站變更一起部署。

Edge Function 需要在 Supabase 專案的 Function Secrets 設定 `SUPABASE_SERVICE_ROLE_KEY`；它只能存在 Supabase 伺服器端，絕不可放入 HTML、JavaScript、GitHub Pages secrets 輸出或前端 `.env`。`SUPABASE_URL` 由 Supabase Function 環境提供。

```powershell
supabase functions deploy admin-create-staff-account
supabase functions deploy admin-manage-staff-account
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="請在本機互動式輸入，不要提交到檔案"
```

## 帳號與員工

`admin_profiles.staff_id` 指向 `staff_members.id`。同一員工只能綁定一個後台帳號；Owner 可不綁定，一般 staff 帳號由建立與編輯 RPC 強制要求綁定。員工隱藏或停用不會自動停用帳號。只有 Owner 可以建立 Owner、將帳號升級為 Owner，或修改 Owner 帳號；Owner 可以建立第二個 Owner。

建立帳號由 `admin-create-staff-account` Edge Function 執行。管理者在後台輸入 Email、初始密碼、顯示名稱、角色、員工與模板；密碼只交給 Supabase Auth 建立 user，資料庫與頁面不保存或顯示它。

## 權限與模板

主要 key：`dashboard.view`、`accounts.view/manage`、`permissions.manage`、`staff.view/manage`、`reservations.view/manage`、`reservation_form.manage`、`orders.view/manage`、`order_specials.manage`、`menu.view/manage`、`reports.view`、`payroll.view/manage`、`game_cards.view/manage`、`scenery_cards.view/manage`、`settings.view/manage`、`roster.view/submit/manage`。

系統模板：Owner、管理員、櫃檯／營運、薪資管理、菜單管理、卡牌管理、一般員工。系統模板不可刪除或編輯；可建立自訂模板並在帳號上再個別調整。授予 `*.manage` 時，系統會在對應 `*.view` 權限存在時一併補上；此規則同時適用於自訂模板、套用模板建立帳號與個別帳號權限儲存。

## 角色與排班權限

`role` 只代表身份分類；實際可操作功能一律依 permission 判斷。即使帳號的 `role = staff`，只要同時具 `roster.manage`，仍可使用完整排班管理介面。反之，只有 `roster.submit` 的綁定員工只能在開放填寫期間維護自己的可上班狀態。

`roster.view` 用於查看目前班表，`roster.submit` 用於本人填寫，`roster.manage` 用於全員矩陣、期間、職位與排班草稿。第一版不把 `roster.publish` 當成排班日常操作流程。

## 後端保護

`has_admin_permission`、`has_any_admin_permission` 與 `ensure_admin_permission` 均為固定 `search_path` 的 `security definer` helper，僅授權 authenticated。RLS 針對員工、菜單、預約、訂單、遊戲卡、月景牌與 Storage 寫入改用對應 key；薪資寫入仍要求 `payroll.manage`，快照讀取改為 `payroll.view`。

## 人工驗收

1. 使用既有 owner 登入，確認首頁仍顯示所有功能與「帳號與權限管理」。
2. 建立一個綁定員工的一般帳號，確認同一員工不能重複綁定。
3. 建立僅有 `reports.view` 的帳號，確認只能看到報表卡片並能載入報表。
4. 建立僅有 `orders.view` 的帳號，確認訂單可讀但更新／刪除被 RLS 拒絕。
5. 以無 `accounts.manage` 帳號呼叫 Edge Function，確認得到 403。
6. 以 staff 或 anon 直接查詢薪資與 `admin_permission_*`，確認被拒絕。
7. 確認 owner 即使沒有 profile-permission 資料，仍可登入並使用所有功能。

## Rollback

先以 SQL Editor 匯出 `admin_profiles` 的新綁定欄位與所有 `admin_permission_*` 表；停止帳號建立頁與 Edge Function 後執行 `20260622040000_admin_permissions.rollback.sql`。Rollback 只移除新權限結構；接著必須依原本部署順序重新執行 `supabase/schema.sql`、`supabase/orders.sql`、`supabase/reservations.sql`、`supabase/storage.sql` 與相關遊戲卡 migration，才能完整還原舊有粗粒度 RLS。

## 密碼與註銷

具 `accounts.manage` 的管理者可為一般帳號設定新的臨時密碼，或註銷帳號。密碼不會被資料庫、前端或 Function log 保存；註銷會刪除 Supabase Auth user 與其連動的後台 profile，無法復原。非 Owner 不能操作 Owner；最後一位啟用 Owner 不可註銷、停用或降級。

## 已知限制

第一版不包含排班通知、排班串薪資與薪資單寄送。
