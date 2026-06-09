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

## 官方文件

- [API keys](https://supabase.com/docs/guides/api/api-keys)
- [Data API](https://supabase.com/docs/guides/api)
- [Auth users](https://supabase.com/docs/guides/auth/users)
- [User management](https://supabase.com/docs/guides/auth/managing-user-data)
- [Database seed](https://supabase.com/docs/guides/local-development/seeding-your-database)
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Upload a file](https://supabase.com/docs/reference/javascript/storage-from-upload)
- [Retrieve public URL](https://supabase.com/docs/reference/javascript/storage-from-getpublicurl)
