# Supabase Phase 1 設定說明

目前網站仍是 GitHub Pages 純前端網站。Supabase 尚未設定、連線失敗或查無資料時，`js/data-provider.js` 會繼續使用原本的本地 JavaScript 資料。

## 1. 建立 Supabase Project

1. 登入 [Supabase Dashboard](https://supabase.com/dashboard)。
2. 建立一個新 project，設定名稱、資料庫密碼與部署區域。
3. 等候 project 建立完成。
4. 妥善保管資料庫密碼，不要放入 GitHub Pages 或前端 JavaScript。

## 2. 建立資料表與 RLS

1. 在 Supabase Dashboard 開啟 **SQL Editor**。
2. 建立一個新 query。
3. 貼上 `supabase/schema.sql` 的完整內容。
4. 執行 query，確認沒有錯誤。
5. 到 **Table Editor** 確認以下資料表已建立：
   - `admin_profiles`
   - `site_settings`
   - `staff_members`
   - `menus`
   - `menu_sections`
   - `menu_items`
6. 確認所有資料表皆已啟用 Row Level Security。

## 3. 匯入初始資料

1. 回到 **SQL Editor**，建立另一個新 query。
2. 貼上 `supabase/seed.sql` 的完整內容。
3. 執行 query，確認網站設定、湯娘與兩份菜單資料均已寫入。
4. `seed.sql` 可重複執行；相同主鍵資料會更新，不會重複新增。

請先執行 `schema.sql`，再執行 `seed.sql`。

## 4. 取得前端連線資訊

Supabase Dashboard 介面可能隨版本調整，目前可從以下位置取得：

- Project URL：**Integrations > Data API**，或 project 的 **Connect** 對話框。
- Publishable key：project 的 **Connect** 對話框，或 **Settings > API Keys**。
- 舊專案亦可使用 **Legacy anon key**。

前端建議使用以 `sb_publishable_` 開頭的 publishable key。不要使用 `sb_secret_`、legacy `service_role`、JWT secret 或資料庫密碼。

## 5. 設定前端 Client

開啟 `js/supabase-client.js`，只替換下列兩個 placeholder：

```js
const config = {
  url: "https://YOUR_PROJECT_REF.supabase.co",
  publishableKey: "YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY",
};
```

填入後範例：

```js
const config = {
  url: "https://abcdefghijk.supabase.co",
  publishableKey: "sb_publishable_xxxxxxxxxxxxxxxxx",
};
```

此檔案會拒絕 `sb_secret_` 與可辨識的 `service_role` key。真正的資料存取權限仍由 PostgreSQL RLS 控制，不可只依賴前端判斷。

## 6. 建立第一個 Auth 使用者

目前尚未建立登入頁，因此第一位使用者需由 Dashboard 建立：

1. 前往 **Authentication > Users**。
2. 使用 Dashboard 的新增使用者功能建立永久使用者，例如使用 email 與密碼。
3. 建立完成後，開啟該使用者並複製 **User ID**。
4. User ID 是 UUID，會對應 `auth.users.id`。

## 7. 將第一位使用者設為 Owner

第一位 owner 必須透過 **SQL Editor** bootstrap，因為此時尚無既有管理員能通過 RLS 寫入 `admin_profiles`。

1. 開啟 `supabase/bootstrap-admin.sql`。
2. 將 `這裡填入 Supabase Auth user id` 替換為剛才複製的 UUID。
3. 視需要修改 `display_name`。
4. 在 SQL Editor 執行。

範例：

```sql
insert into public.admin_profiles (
  id,
  display_name,
  role,
  is_active
) values (
  '這裡填入 Supabase Auth user id',
  '吹雪',
  'owner',
  true
);
```

完成後可用以下 SQL 確認：

```sql
select id, display_name, role, is_active
from public.admin_profiles;
```

## 8. 安全注意事項

- GitHub Pages 的 JavaScript 對任何訪客都可見，只能放 publishable key 或 legacy anon key。
- 絕對不要將 `sb_secret_`、legacy `service_role`、JWT secret、資料庫密碼放入前端或提交到 Git。
- Publishable key 本來就是公開識別資訊，資料安全必須依靠 RLS。
- 建立使用者不會自動取得 owner/admin 權限，仍需有對應的 `admin_profiles` 資料。
- `staff` 角色目前沒有內容寫入 policy。
- `_image_backup/` 已由 `.gitignore` 排除，不可加入 GitHub Pages 部署內容。
- 若 `_image_backup` 曾被 Git 追蹤，需在實際 Git repository 執行：

  ```bash
  git rm -r --cached _image_backup
  git commit -m "Remove image backup from deployment"
  ```

上述指令只停止 Git 追蹤，不會刪除本機備份。

## 9. 驗證

依照 `supabase/smoke-test.md` 逐項測試。正式啟用前，也應在 Supabase Dashboard 的 Security Advisor 檢查 RLS 與權限警告。

## 10. 湯娘圖片 Storage

湯娘管理使用既有 public bucket：`heyotsuki-images`。

1. 在 Supabase Dashboard 的 **Storage** 確認 bucket `heyotsuki-images` 已存在。
2. 確認 bucket 為 public，否則 `getPublicUrl()` 產生的網址無法直接顯示。
3. 在 **SQL Editor** 執行 `supabase/storage.sql`。
4. 圖片會上傳到 `staff/` 資料夾，格式為：

   ```text
   staff/{yyyyMMdd-HHmmss}-{slug}.webp
   ```

5. 前端只使用 publishable/anon key。不要使用 `service_role`、`sb_secret_` 或 GitHub token。
6. Storage 寫入由 `storage.objects` RLS 與 `public.is_content_admin()` 控制。
7. `staff` 角色不可新增、更新或刪除圖片。
8. 後台不會自動刪除舊圖片，避免仍被其他資料引用。
9. 上傳圖片只存在 Supabase Storage，不應加入 GitHub repository。

詳細測試請參考 `docs/staff-admin-test.md`。

## 10-A. 遊戲卡設定與專用圖片

遊戲卡設定沿用 `staff_members` 作為員工名稱、一般照片、官網顯示狀態與排序的來源。

依序執行：

```text
supabase/migrations/20260615090000_game_staff_card_settings.sql
supabase/migrations/20260615100000_allow_game_card_auto_assign_trusted_roles.sql
supabase/migrations/20260615103000_fix_game_card_auto_assign_conflict.sql
supabase/storage.sql
```

後兩個 migration 是自動分配 hotfix。全新環境的第一個 migration 已包含相同修正；既有環境依序套用尚未執行的 hotfix 即可。

Migration 會建立：

- `public.game_staff_card_settings`
- `public.get_game_month_catalog()`
- `public.get_active_game_staff_cards()`
- `public.auto_assign_unset_game_staff_cards()`
- updated_at trigger、index、RLS、grants

`get_active_game_staff_cards()` 是正式遊戲卡池的唯一公開讀取介面。它只回傳：

- `staff_members.is_visible = true`
- `is_game_enabled = true`
- 月份與印記設定完整
- 專用圖片或一般員工圖片至少有一個可用值

此 RPC 不會使用 `js/data-staff.js` 或其他本地名單備援。讀取失敗時，正式遊戲必須阻止開局。

Storage 使用同一個 public bucket：

```text
staff/       官網一般員工照片
game-cards/  遊戲專用卡面
```

兩個子目錄都只有有效 owner/admin 可寫入。遊戲專用圖片未設定時，RPC 會沿用 `staff_members.image_url`。
由於遊戲會獨立部署，正式啟用前必須確認 RPC 回傳的圖片 URL 可由遊戲網域直接載入。既有 seed 中的相對圖片路徑適合官網本身；正式遊戲卡建議將一般照片更新為 Storage public URL，或為該卡設定 `game-cards/` 專用圖片。

月份與季節集中由 `get_game_month_catalog()` 提供：

- 春：1–3 月
- 夏：4–6 月
- 秋：7–9 月
- 冬：10–12 月

後台不提供獨立季節欄位。自動分配 RPC 只新增尚未建立設定的員工，不更新既有設定；月份平手依 1–12 月，印記平手依 moon、bell、fan、knot。
自動分配可由 owner/admin 後台、Dashboard SQL Editor 或 API `service_role` 執行；anon、一般 authenticated 與 staff 仍會被函式拒絕。

Rollback：

```text
supabase/migrations/20260615090000_game_staff_card_settings.rollback.sql
```

Rollback 不會刪除 `staff_members` 或 Storage 圖片。若也要撤回 `game-cards/` 寫入權限，需將 `supabase/storage.sql` 的允許子目錄恢復為只有 `staff` 後重新執行。

驗證文件：

- `supabase/game-card-smoke-test.sql`
- `docs/game-card-admin-test.md`

## 11. 預約管理

Phase 2-A 需要在完成 `supabase/schema.sql` 後，於 SQL Editor 執行：

```text
supabase/reservations.sql
```

此檔案會建立預約資料表、表單模板、預約時段、例外日期、預設欄位與 RLS policies。執行後請確認 Table Editor 中可看到 `reservations`、`reservation_form_settings`、`reservation_time_slots`、`reservation_date_overrides`、`reservation_form_fields` 與 `reservation_form_options`。

若 Phase 2-A 基礎表已經建立，再執行：

```text
supabase/reservation-availability-migration.sql
```

此 migration 會加入可預約湯娘、第二位指定湯娘、預約日期窗口、公開 availability RPC 與有效時段唯一索引，不會刪除既有預約資料。若既有資料中已存在同日期、同時段且狀態為 `pending` / `confirmed` 的重複預約，請先人工處理衝突資料，再建立唯一索引。

## 官方文件

- [API keys](https://supabase.com/docs/guides/api/api-keys)
- [Data API](https://supabase.com/docs/guides/api)
- [Auth users](https://supabase.com/docs/guides/auth/users)
- [User management](https://supabase.com/docs/guides/auth/managing-user-data)
- [Database seed](https://supabase.com/docs/guides/local-development/seeding-your-database)
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Upload a file](https://supabase.com/docs/reference/javascript/storage-from-upload)
- [Retrieve public URL](https://supabase.com/docs/reference/javascript/storage-from-getpublicurl)
