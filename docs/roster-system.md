# 排班系統第一版

## 範圍與流程

第一版排班系統只處理可上班狀態、職位需求、手動排班、自動補班與班表輸出，不包含打卡、請假、換班、通知或薪資自動串接。

目前操作流程為：

```text
建立排班期間
-> 開放員工填寫
-> 關閉填寫
-> 管理員排班與調整
-> 輸出班表圖或文字版
```

薪資公共池仍由薪資頁手動選人；排班資料不會自動改變薪資分潤。

## 期間狀態

| 資料庫狀態 | 介面文案 | 第一版意義 |
| --- | --- | --- |
| `open` | 開放填寫 | 綁定員工可填寫自己的可上班狀態。 |
| `draft` | 已關閉填寫 | 員工可查看自己的資料但不可自行修改；管理員可代填、排班與調整草稿。 |

`published` 與 `locked` 仍保留在資料結構中，以維持既有歷史資料相容與未來擴充空間；第一版不使用發布或鎖定流程，也不把它們當作日常操作步驟。

## 資料設計

- `roster_periods`：排班期間與狀態。
- `roster_shift_slots`：期間內各日期與班別。
- `roster_roles`：可自訂職位與每班最少／最多人數。
- `roster_period_role_requirements`：建立期間時的職位需求快照。
- `roster_availability`：員工每一班的 `unselected`、`available`、`unavailable`、`standby` 狀態。
- `roster_assignments`：目前班表草稿的人員安排；`pending` 表示待定。

## 員工填寫

1. 有綁定 `admin_profiles.staff_id` 且具 `roster.submit` 的帳號可填寫本人可上班狀態。
2. `open` 時顯示「目前開放填寫，請填寫自己的可上班狀態。」並允許儲存。
3. `draft` 時顯示「目前已關閉填寫，如需修改請聯絡管理員。」並保留唯讀查看。
4. 一般員工只能讀寫自己綁定的員工資料，不能查看或修改其他人的 availability。

## 管理員操作

具 `roster.manage` 的帳號可管理完整矩陣、期間、班別、職位與排班草稿；是否可管理只看 permission，不看帳號角色是否為 `staff`。

1. 建立期間後預設為 `open`。
2. 管理員可隨時以「關閉填寫」切換為 `draft`，再使用「開放填寫」重新開放。
3. 管理員可在 open 或 draft 代填可上班狀態、手動安排人員及使用每班的自動排班。
4. 班表預覽可輸出本日 PNG 或複製文字版；這是目前班表，不是正式發布流程。

## 自動排班規則

1. 僅使用 `available`；勾選使用備用人員時才納入 `standby`。
2. 不使用 `unselected` 或 `unavailable`。
3. 同一班別同一員工不會被自動排入多個職位。
4. 手動人員會被保留；可對單一班別自動補空缺。
5. 可手動選取人員時只會顯示該班標示為可或備用的人員。

## 權限

- `roster.view`：查看目前班表與期間。
- `roster.submit`：在 open 期間填寫自己綁定員工的可上班狀態。
- `roster.manage`：管理全部期間、班別、職位、矩陣與草稿；管理權限同時可代填資料。

第一版不需要 `roster.publish` 作為操作流程的一部分。

## 部署順序

1. 確認 `20260622040000_admin_permissions.sql` 與 `20260622050000_admin_permissions_hotfix_1.sql` 已套用。
2. 依序套用：
   - `20260622060000_roster_system_v1.sql`
   - `20260622061000_roster_period_workflow_hotfix.sql`
   - `20260622062000_roster_period_and_role_usability_hotfix.sql`
   - `20260622063000_roster_open_submission_status_hotfix.sql`
   - `20260622064000_roster_closed_period_readonly_visibility.sql`
   - `20260622065000_roster_closed_period_structure_guard.sql`
   - `20260622066000_roster_role_manual_ordering.sql`
   - `20260623010000_roster_assignment_draft_and_optional_autofill.sql`
   - `20260623011000_roster_optional_autofill_available_only.sql`
   - `20260623012000_roster_skip_unavailable_auto_pending.sql`
   - `20260623013000_roster_period_date_guard.sql`
   - `20260623014000_roster_generate_single_shift.sql`
   - `20260623015000_roster_assignment_availability_guard.sql`
3. 部署 `admin/roster.html`、`js/admin-roster.js`、`js/admin-auth.js`、`admin/index.html` 與 `css/admin.css`。

不需要 Storage policy、Edge Function、service role 或 Realtime 設定。

## 人工驗收

1. 綁定員工且只有 `roster.view`、`roster.submit` 的 staff 只能填自己的資料。
2. 具 `roster.manage` 的 staff、admin 或 owner 都可看到完整管理介面。
3. 綁定 staff 的管理員可在「我的狀態」填自己資料；未綁定的管理員仍可管理全員資料且不報錯。
4. open 顯示「開放填寫」，draft 顯示「已關閉填寫」。
5. draft 時一般員工不可寫入，管理員仍可調整 availability 與草稿。
6. PNG 與文字輸出正常，且不包含後台按鈕。

## 已知限制

第一版不處理跨店、換班、請假、出勤、通知與薪資自動串接。`published`／`locked` 只作未來擴充保留，非目前排班流程。
