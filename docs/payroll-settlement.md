# 薪資分潤結算

薪資分潤只處理菜單品項分配；不處理小費、泡湯收入、排班或員工自行查詢。

## Migration 順序

依序執行：

1. `supabase/migrations/20260620050000_staff_payroll_settlement.sql`
2. `supabase/migrations/20260620061000_payroll_admin_usability.sql`
3. `supabase/migrations/20260620062000_payroll_reservation_direct_staff_pool_exclusion.sql`
4. `supabase/migrations/20260622010000_payroll_settlement_lock_and_dance_hotfix.sql`
5. `supabase/migrations/20260622020000_payroll_direct_assignment_and_locked_entries.sql`
6. `supabase/migrations/20260622030000_payroll_manual_dance_supplements.sql`

## 分潤規則

- `food_pool`：餐點公共池，依已勾選成員人頭平均分配；尾數按勾選順序分配。
- `direct_staff`：受益人依序採用薪資草稿補選、訂單品項原本的 `selected_staff_id`；兩者都沒有時列為待分配。
- `dance_split`：訂單數量就是必須建立的場次數。每場金額由訂單行快照總額除以數量計算，尾數依場次序號由前至後分配。
- `excluded`：不進薪資分潤。

例如 `320,000 / 4` 為四場各 `80,000`；`100,001 / 3` 為第 1、2 場 `33,334`、第 3 場 `33,333`。每場再依參與者登記順序人頭平均，尾數同樣依順序分配。

若舞蹈訂單應有 N 場但有效場次少於 N，重算會建立待分配項目並阻擋鎖定。場次沒有參與者也會阻擋鎖定。

## 補登舞蹈分潤

臨時舞蹈若未建立訂單，可直接在欲歸屬的營業日薪資批次新增「補登舞蹈分潤」。它只存在薪資分潤模組，不建立或修改訂單，也不影響營業額與營業報表。

補登必填金額、原因與至少一位參與員工；金額會依參與員工的勾選順序平均拆分，尾數由前面的員工取得。系統在該批次內自動編號為「補登舞蹈 #1、#2」等。可輸入負數建立沖銷／更正紀錄。

補登可在草稿與已鎖定批次新增。每筆補登與其分配明細均為 append-only：儲存後不可修改或刪除；若填寫錯誤，請以相同參與者新增一筆反向金額補登。這保留原始 locked 快照，同時讓後續補登可被稽核。補登會出現在薪資預覽、員工合計、CSV 與文字摘要。

## 公共池預約排除

公共池名單預設排除當日有泡湯預約、且狀態不是下列兩種的員工：

- `cancelled`
- `no_show`

目前實際預約狀態為：`pending`、`confirmed`、`cancelled`、`completed`、`no_show`。因此 `pending`、`confirmed`、`completed` 都會排除；取消與未到場不排除。

此規則只影響公共池候選名單，不影響舞蹈場次的完整員工勾選名單，也不以點餐 `selected_staff_id` 排除公共池。被排除者不會出現在公共池可勾選列表；頁面只會以一行摘要顯示排除名單與原因。

## 直接歸屬待分配補選

拍立得、占卜或其他 `direct_staff` 品項若缺少受益員工，可在薪資草稿的「待分配項目」選擇員工並儲存。補選會寫入 `payroll_source_assignments`，記錄 `batch_id`、`source_type`、`source_id`、`assigned_staff_id`、建立與更新時間及操作者；不會修改原始訂單或 `order_items.selected_staff_id`。

補選後系統立即重算，該項目會改為直接歸屬薪資明細。已鎖定批次不可新增、修改或刪除補選。

## 鎖定流程

`lock_payroll_batch()` 在單一交易內：

1. 鎖定草稿批次列。
2. 以目前公池、舞蹈場次、參與者與直接歸屬重新產生薪資明細。
3. 檢查待分配項目與是否有產生明細。
4. 檢查系統分配總額與來源可分配總額一致。
5. 全數通過才把批次標記為 `locked`。

管理者不需要先手動按「重算明細」，但可以先重算預覽結果。

## 手動調整

`manual_adjustment` 是例外薪資明細，不是一般分潤規則。建立時必須選員工、填金額與原因；它會出現在預覽、員工合計、CSV 與文字摘要中。`payroll_entries_prevent_locked_changes` 實際掛載 `prevent_locked_payroll_entry_changes()`；鎖定後整個批次明細固定，包含手動調整在內均不能新增、修改或刪除。

## 小費

拍立得、占卜、跳舞小費由客人直接交給喜歡的店員；點餐小費充公。全部不進薪資分潤，系統不會產生 `tip` 類型薪資明細。

## 部署與回滾

部署時先套用上述 migration，再部署：

- `admin/payroll.html`
- `js/admin-payroll.js`

不需要重跑 Storage Policy 或 Realtime Publication。

Hotfix 套用前請先匯出草稿 `payroll_source_assignments` 與所有 `payroll_manual_dance_*` 資料。若必須回退，先停止使用薪資頁，先執行 `supabase/migrations/20260622030000_payroll_manual_dance_supplements.rollback.sql`，再視需要執行 `supabase/migrations/20260622020000_payroll_direct_assignment_and_locked_entries.rollback.sql`。補登 rollback 會移除 payroll-only 補登紀錄，不會修改訂單；不要回滾或刪除已鎖定批次。
