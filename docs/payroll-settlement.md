# 薪資分潤結算

本功能屬於官網後台 `Heyotsuki-Yado`，不影響花札遊戲專案。

## 套用順序

1. 先確認既有點餐系統已套用：
   - `supabase/orders.sql`
   - `supabase/order-reports.sql`
2. 再執行：
   - `supabase/migrations/20260620050000_staff_payroll_settlement.sql`
   - `supabase/migrations/20260620061000_payroll_admin_usability.sql`

Rollback：

```sql
\i supabase/migrations/20260620061000_payroll_admin_usability.rollback.sql
\i supabase/migrations/20260620050000_staff_payroll_settlement.rollback.sql
```

Rollback 只移除薪資分潤新增的表、RPC、trigger 與 policy，不會修改 `orders`、`order_items`、`menu_items` 或 `staff_members`。

## 權限

- `owner` / `admin` 可管理薪資分潤。
- `staff` 目前不可查看完整薪資資料。
- `anon` 沒有任何薪資資料權限。
- 所有正式操作走 RPC，RPC 會使用目前登入者 `auth.uid()` 判斷權限。
- 前端不可放 service role 或其他私密金鑰。

## 分潤規則

每個 `menu_items` 可設定一種薪資規則：

- `food_pool`：公池平均分配。
- `direct_staff`：指定員工取得。
- `dance_split`：舞蹈場次分配。
- `excluded`：不列入薪資。

規則只影響薪資結算，不改變公開菜單、點餐送出、限量或報表邏輯。

## 結算資料來源

薪資結算只讀取訂單快照：

- `orders.shop_key`
- `orders.business_date`
- `orders.status`
- `orders.deleted_at`
- `order_items.item_name_snapshot`
- `order_items.selected_staff_id`
- `order_items.selected_staff_name_snapshot`
- `order_items.line_total_amount_snapshot`
- `order_items.price_amount_snapshot`
- `order_items.options_amount_snapshot`
- `order_items.quantity`

符合條件：

- `orders.deleted_at is null`
- `orders.status in ('pending', 'accepted', 'preparing', 'served')`
- `business_date` 符合批次營業日

`cancelled` 與軟刪除訂單不進入薪資結算。

## 批次流程

1. 到 `admin/menu.html` 為品項設定薪資分潤規則。
2. 到 `admin/payroll.html` 選店別與營業日。
3. 建立或讀取薪資批次。
4. 設定公池成員。公池可勾選名單會預設排除當日已指名員工；舞蹈場次參與者仍可從完整員工清單勾選。
5. 數量為 1 的未建舞蹈品項可批次建立空場次，再逐場勾選參與者。
6. 同一筆訂單數量不等於 1、需要拆場或金額需要調整時，再手動新增場次；場次編號由系統依目前啟用場次自動補上。
7. 點擊「重算明細」產生薪資明細。
8. 處理所有待分配項目。
9. 鎖定批次。

鎖定後不可重算或修改公池、舞蹈場次與既有明細。若鎖定後需要補差額，請新增「調整項」。

## 規則細節

### 公池平均

`food_pool` 品項總額依公池成員人頭平均分配。若不能整除，餘數依勾選順序固定分配，總額必須與來源總額完全一致。

若有公池金額但沒有設定公池成員，會產生待分配項目。

### 指定員工

`direct_staff` 直接分配給 `order_items.selected_staff_id`。

若訂單品項沒有指定員工，會列入待分配清單，不自動猜測員工。

### 舞蹈場次

`dance_split` 需要建立舞蹈場次並設定參與員工。數量為 1 且尚未建立場次的舞蹈品項，可在後台批次建立空場次。

同一筆訂單數量不等於 1、需要拆成多場，或實際分配金額不同時，由管理者手動新增場次。

刪除場次採軟刪除，會將場次標示為作廢，不列入薪資計算，也不占用下一次新增場次的編號。

每個場次金額依參與員工人頭平均分配。若不能整除，餘數依參與者順序固定分配。

若舞蹈品項尚未建立場次，或場次沒有參與者，會列入待分配清單。

### 調整項

調整項會寫入 `payroll_entries.source_type = 'manual_adjustment'`，並保存建立者與原因。這是鎖定後修正差額的正式方式。

## 測試期間清除當日計算資料

以下 SQL 只會清除指定店別與營業日的薪資批次、舞蹈場次、參與者與薪資明細，不會刪除訂單、菜單或員工資料。請先確認 `shop_key` 與 `business_date`。

```sql
with target_batch as (
  select id
  from public.payroll_batches
  where shop_key = 'menu'
    and business_date = date '2026-06-20'
)
delete from public.payroll_batches
where id in (select id from target_batch);
```

`payroll_entries`、`payroll_pool_members`、`dance_sessions`、`dance_session_participants` 會因外鍵 cascade 一併清除。若批次已鎖定，建議仍只在測試資料上執行。

## 不影響項目

本功能不修改：

- 公開官網頁面
- 公開點餐頁面
- 訂單送出 RPC
- 限量機制
- Discord 推播
- 銷售報表
- 員工 CRUD
- 花札遊戲

## 手動驗證

請參考 `docs/payroll-settlement-test.md`。
