# Phase 2-B-1 分店式點餐系統

## 建置

1. 確認 Phase 1 的 `supabase/schema.sql` 已執行。
2. 到 Supabase SQL Editor 執行 `supabase/orders.sql`。
3. SQL 可重複執行，會建立訂單資料表、店別權限、隱藏料理名單、RPC、RLS 與 trigger。
4. 執行後重新部署 GitHub Pages 前端檔案。

## 前台網址

- `order-yado.html`：湯宿點餐，固定使用 `shop_key = menu`。
- `order-kissa.html`：喫茶點餐，固定使用 `shop_key = menu2`。

兩頁不放進主要導覽，適合由店員在遊戲內直接傳送網址。客人不需登入，也不需填桌號。

前台透過 `get_public_order_menu` 讀取菜單，並透過 `submit_order` 送出。anon 不會取得 `orders` 或 `order_items` 的直接資料表權限。

## 點餐營業時間

每間店可在 `admin/menu.html` 的「點餐營業設定」獨立管理：

- `auto`：依開放星期與營業時間自動開關。
- `open`：手動強制開放，不受目前星期與時間限制。
- `closed`：手動強制關閉。

營業判斷使用 `Asia/Taipei`，不會解析 `site_settings.openingHours` 等顯示文字。非營業時間仍可查看菜單，但不能加入品項或送出。

時間以分鐘保存。一般 21:00 到 24:00 為 `1260` 到 `1440`；跨日 22:00 到 01:00 為 `1320` 到 `1500`。後台可直接輸入 `22:00`、`01:00`，儲存時會自動換算跨日分鐘。

`get_order_shop_open_state` 負責產生點餐狀態、營業日期與可選時段。`submit_order` 會再次呼叫此函式驗證，不能只靠前端禁用繞過。

客人選擇的時間保存於 `orders.requested_time`。`orders.business_date` 保存對應營業日，例如星期六 00:30 的跨日訂單會記為星期五。

用餐／出餐時間欄位可用 `order_time_visible` 個別控制。關閉後，前台不顯示時間欄位、`requested_time` 會寫入 `null`，但營業星期與營業時間仍會繼續判斷點餐是否開放。

## staff 店別權限

owner／admin 可管理全部店別。staff 僅能使用 `admin_shop_permissions` 授權的店別與操作。

```sql
insert into public.admin_shop_permissions (
  user_id,
  shop_key,
  can_view_orders,
  can_update_orders,
  can_delete_orders
) values (
  '填入 admin_profiles.id',
  'menu',
  true,
  true,
  false
)
on conflict (user_id, shop_key) do update set
  can_view_orders = excluded.can_view_orders,
  can_update_orders = excluded.can_update_orders,
  can_delete_orders = excluded.can_delete_orders;
```

`menu` 是湯宿，`menu2` 是喫茶。staff 預設不應取得刪除權限。

## 品項員工名單

預約指定與點餐員工名單是兩套獨立設定：

- 預約指定使用 `staff_members.is_reservable`。
- 點餐品項使用 `menu_item_staff_options`。

每個品項各自設定人員。例如湯娘隱藏版可設定 A／B，拍立得可設定 B／C。請到 `admin/order-specials.html` 先選店別與品項，再設定該品項的顯示名稱、選項文字、排序與備註。

菜單品項如需選擇人員，可在 `admin/menu.html` 勾選 `requires_staff_selection`，並設定 `staff_selection_label`。取消 `is_orderable` 後，品項仍可留在公開菜單，但不會出現在點餐頁。

需要選人員的品項可使用「新增一份」建立多筆 cart line，因此同一張訂單可分別選擇不同湯娘／員工。

舊 `staff_order_specials` 會保留，但新版前台與 `submit_order` 不再依賴它。如需把舊名單複製為品項級名單，可選擇性執行：

```sql
insert into public.menu_item_staff_options (
  menu_item_id, staff_id, display_name, option_label,
  note, is_visible, sort_order
)
select
  menu_items.id,
  staff_order_specials.staff_id,
  staff_order_specials.display_name,
  staff_order_specials.special_label,
  staff_order_specials.note,
  staff_order_specials.is_visible,
  staff_order_specials.sort_order
from public.staff_order_specials
join public.menu_sections
  on menu_sections.menu_key = staff_order_specials.shop_key
join public.menu_items
  on menu_items.section_id = menu_sections.id
  and menu_items.requires_staff_selection = true
on conflict (menu_item_id, staff_id) do nothing;
```

複製後仍需到品項員工設定頁逐項調整。

## 加購選項

`menu_item_order_options` 用於 checkbox 加購。例如「拍立得」可建立：

- 名稱：簽繪版本
- `price_delta_amount = 20000`
- `price_delta_text = +20,000 Gil`
- `requires_staff_capability = true`

能力型加購透過 `menu_item_order_option_staff` 設定可提供人員。未勾簽繪時使用拍立得本身的品項員工名單；勾選後再與簽繪能力名單取交集。

加購內容會保存於 `selected_options_snapshot`，加購合計保存於 `options_amount_snapshot`，每筆小計保存於 `line_total_amount_snapshot`。舊訂單沒有加購快照時仍可正常顯示。

### 加購選項本日限量

`menu_item_order_options.order_limit_quantity` 可針對單一加購選項設定每日限量：

- `null`：不限量。
- `0`：售完。
- 正整數：該加購選項當日可被選取的總份數。

前台公開菜單會回傳每個加購選項的 `remaining_quantity`。送出訂單時，`submit_order()` 會以營業日與加購選項 ID 加交易鎖，並重新計算有效訂單中已使用的數量，避免同時送單造成超賣。

計算占用量時只包含未刪除且狀態為 `pending`、`accepted`、`preparing`、`served` 的訂單；已取消或軟刪除訂單不占用加購限量。

### 加購選項個人限量

若加購選項勾選 `requires_staff_capability`，可在可提供人員清單中針對每位人員設定個人每日限量，資料存於 `menu_item_order_option_staff.order_limit_quantity`：

- `null`：該人員不限量。
- `0`：該人員今日不可再提供此加購。
- 正整數：該加購選項底下，該人員當日可被選取的份數。

個人限量只在該加購選項需要選擇合格人員時生效。前台選取加購後，指定人員下拉會顯示該人員剩餘數；送出時 `submit_order()` 會再次依營業日、加購選項與 `selected_staff_id` 檢查，避免超賣。若同時設定加購選項總量與個人限量，兩者都必須有足夠剩餘量。

## 本日限量

在 `admin/menu.html` 的品項編輯區設定 `order_limit_quantity`：

- 留空：不限量。
- `0`：售完／不可點。
- 大於 `0`：本日最多可接受的總份數。

本日以 `Asia/Taipei` 的 `business_date` 計算。跨日營業的凌晨訂單仍算在前一個營業日。`pending`、`accepted`、`preparing`、`served` 訂單會占用限量；`cancelled` 或已軟刪除訂單不占用。

`get_public_order_menu` 會回傳剩餘數量，`submit_order` 也會在資料庫 transaction 中使用 advisory lock 重新檢查，避免兩位客人同時送出造成超賣。

## 點餐欄位

每個品項可用 `allow_item_note` 控制是否顯示品項備註。關閉後前台不顯示欄位，RPC 也會忽略惡意傳入的 `item_note`。

每個店別可分別設定：

- `order_customer_label`：角色欄位名稱，預設「角色 ID」。
- `order_contact_visible`／`order_contact_required`：聯絡方式顯示及必填。
- `order_note_visible`／`order_note_required`：整筆訂單備註顯示及必填。
- `order_time_visible`／`order_time_required`：用餐／出餐時間顯示及必填。

隱藏欄位即使被前端惡意送入，`submit_order` 仍會寫入 `null`。

後台訂單卡片也依目前店別設定顯示欄位。聯絡方式、客人備註或用餐時間被隱藏後，後台不會再渲染對應欄位，也不會顯示「未填寫」。聯絡方式隱藏時，後台搜尋只搜尋角色 ID。

## Snapshot

`order_items` 會保存品項名稱、價格及指定人員快照。即使後續菜單改名、改價或人員設定變動，歷史訂單仍顯示送出當下的內容。

後台訂單品項依序顯示：

1. 品項名稱與數量。
2. 指定員工。
3. 原始單價。
4. 加購選項清單。
5. 品項備註。
6. 該筆小計。

菜單品項名稱建議只使用基礎名稱，例如「拍立得」。「簽繪版本 +20,000 Gil」應建立為 `menu_item_order_options` 加購選項，不建議同時寫在品項名稱與加購資料中，避免管理畫面看起來重複。

## 新訂單提示

`admin/orders.html` 會優先使用 Supabase Realtime 監聽 `public.orders` 的 INSERT。事件只用於增加有權限店別的未讀提示；完整訂單仍透過原本受 RLS 保護的查詢載入。

若要取得即時事件，需在 Supabase 啟用 `orders` 的 Realtime publication。頁面同時保留每 30 秒安全輪詢並以訂單 ID 去重，因此即使資料表未加入 publication、訂閱無事件或連線中斷，仍可偵測新訂單。新訂單會顯示頁內提示、店別 badge、頁籤標題未讀數，並在分頁 favicon 疊上紅色未讀數字。只有尚未查看的新訂單會顯示 favicon badge，重新載入該店訂單後會恢復原圖示。為避免覆蓋正在編輯的管理備註，頁面不會強制重繪，需點擊提示重新載入。

提示音預設關閉。使用者手動勾選「啟用提示音」後，頁面會解鎖瀏覽器音訊並播放一次較明顯的雙音確認提示。設定會保存於 `localStorage` 的 `heyotsuki.orderSoundEnabled`，不使用外部音檔。瀏覽器重新開啟分頁後若尚未允許自動播放，頁面會提示使用者關閉後重新啟用提示音。

## MVP 範圍

- 點餐 Discord 推播由 `notify-order-discord` Edge Function 處理，部署方式請參考 `docs/discord-order-notify.md`。
- 不與預約系統連動。
- 沒有桌號或客人登入。
- 沒有付款、金流或庫存功能。
