# 點餐銷售報表

## 部署 SQL

1. 先在 Supabase SQL Editor 重新執行 `supabase/orders.sql`。
2. 再執行 `supabase/order-reports.sql`。

`orders.sql` 會為 `order_items` 加入菜單與分類快照欄位，並讓新訂單保存當下的店別、分類與品項排序。`order-reports.sql` 會建立：

- `get_order_report_default_business_date(p_shop_key)`
- `get_order_sales_report(...)`

兩個 RPC 都只授權 `authenticated`。owner／admin 可查所有店別，staff 只能查 `admin_shop_permissions.can_view_orders = true` 的店別，anon 無法執行。

## 報表日期

報表以 `orders.business_date` 為準，不直接使用 `created_at::date`。

跨日營業例如 22:00 至 01:00，凌晨 00:30 的訂單仍屬於前一個營業日。舊訂單若沒有 `business_date`，才 fallback 到：

```sql
(orders.created_at at time zone 'Asia/Taipei')::date
```

後台預設日期由 `get_order_report_default_business_date()` 取得，使用各店目前的點餐營業設定判斷；無法取得時，前端才使用 Asia/Taipei 今日日期。

## 計算規則

預設列入：

- `pending`
- `accepted`
- `preparing`
- `served`

`cancelled` 預設不列入，但可在後台手動勾選。`deleted_at is not null` 永遠排除。

品項金額優先使用 `line_total_amount_snapshot`。若舊資料沒有此欄位，使用：

```text
(price_amount_snapshot + options_amount_snapshot) × quantity
```

加購金額會計入原品項 subtotal，不拆成獨立大項。若仍無法計算，該明細以 0 計入並出現在報表 warnings。

## 分類快照

新訂單會保存：

- `menu_key_snapshot`
- `menu_title_snapshot`
- `section_id_snapshot`
- `section_title_snapshot`
- `section_sort_order_snapshot`
- `item_sort_order_snapshot`

因此日後分類改名或品項移動時，舊訂單仍能保留當時分類。舊訂單缺少快照時，報表會 fallback 到目前的 `menu_items → menu_sections → menus` 關聯；若品項也已無法關聯，歸入「未分類」。

## 後台使用

進入 `admin/reports.html`：

1. 選擇店別。
2. 選擇起始與結束營業日。
3. 選擇要列入的訂單狀態。
4. 點擊「產生報表」。
5. 可匯出 CSV 或複製文字摘要。

畫面會顯示訂單數、品項數量、總金額、分類 subtotal 與品項 subtotal。

## CSV

CSV 欄位：

```text
層級,大項,小項,數量,金額,備註
```

金額使用純數字，方便 Excel 計算。檔案包含 UTF-8 BOM，並在文字欄位進行試算表公式注入防護，不需要外部 CDN 或 XLSX 套件。

檔名範例：

```text
heyotsuki-order-report-menu-2026-06-10.csv
```

## 第一版範圍

- 只有點餐銷售統計。
- 沒有排班系統。
- 沒有自動分潤規則。
- 沒有付款或金流。
- 報表系統本身不處理 Discord 推播。
- 沒有 XLSX 多工作表匯出。
