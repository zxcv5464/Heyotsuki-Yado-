# 預約 Discord 推播部署

## 安全原則

Discord webhook URL 與 Supabase service role key 都是伺服器端機密，不可放入：

- GitHub Pages 的 HTML 或 JavaScript
- `js/site-config.js`
- `js/supabase-client.js`
- Git repository

前端只能使用 Supabase publishable key 或 anon key。Edge Function 使用 service
role 查詢及更新預約資料，資料庫 RLS 不會因此對訪客放寬。

`supabase/.temp/` 是 Supabase CLI 產生的暫存連線資訊，已由 `.gitignore`
排除，不可提交到 GitHub。

## 設定 Edge Function secrets

先安裝 Supabase CLI、登入並連結 project：

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

設定必要 secrets：

```bash
supabase secrets set \
  DISCORD_RESERVATION_WEBHOOK_URL="https://discord.com/api/webhooks/..." \
  SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY"
```

可選擇設定營業時間 fallback：

```bash
supabase secrets set \
  DISCORD_RESERVATION_BUSINESS_HOURS="週五 至 週日 PM 21:00 — 24:00"
```

Discord 推播會優先讀取 `site_settings` 的 `openingDays` 與 `openingHours`。
只有資料庫查詢失敗或缺少任一設定時，才使用
`DISCORD_RESERVATION_BUSINESS_HOURS`；該 secret 也未設定時，最後使用程式內
單一預設值。

後台網站設定管理更新 `openingDays` 或 `openingHours` 後，下一次 Discord
推播會直接使用新內容，不需要重新部署 Edge Function。

`SUPABASE_SERVICE_ROLE_KEY` 只能存在 Supabase Edge Function secrets。不要將
含有真實 secret 的完整指令保存到文件、Shell script 或 Git。

確認 secret 名稱：

```bash
supabase secrets list
```

## 部署資料庫收尾

在 Supabase SQL Editor 執行：

```text
supabase/reservation-release-cleanup.sql
```

此 migration 會：

- 將預約日期起算改為 `Asia/Taipei`
- 確保 availability RPC 使用 `SECURITY DEFINER`
- 設定安全的 `search_path`
- 撤銷 anon 直接讀取 `reservation_date_overrides`
- 保留 anon 執行 availability RPC 的權限

## 部署 Edge Function

從專案根目錄執行：

```bash
supabase functions deploy notify-reservation-discord
```

此 Function 接受 GitHub Pages 使用 publishable/anon session 呼叫，因此保留
Supabase 預設 JWT 驗證，不需要使用 `--no-verify-jwt`。

查看執行紀錄：

```bash
supabase functions logs notify-reservation-discord
```

## 前台測試

1. 開啟 `reservation.html`。
2. 填寫並送出一筆可用時段的測試預約。
3. 前台應顯示「已收到您的預約，請等待店家確認。」
4. Discord 頻道應收到「嘿月湯宿｜入宿預約通知」embed。
5. 確認 embed 的營業時間與後台網站設定一致。
6. 在 `reservations` 檢查：
   - `discord_status` 為 `sent`
   - `discord_attempts` 增加 1
   - `discord_notified_at` 有時間
   - `discord_last_error` 為空

Discord 推播失敗不會取消預約。即使 webhook 暫時失敗，前台仍顯示預約成立。

## 後台重新推送

1. 使用 owner 或 admin 登入 `admin/reservations.html`。
2. 找到要重新推送的預約。
3. 點擊「重新推送 Discord」並確認。
4. 成功後列表會重新載入並更新 Discord 狀態。

staff 可以查看 Discord 狀態，但不會看到修改與重新推送按鈕。已軟刪除的預約
不提供重新推送。

## 失敗排查

後台預約卡片會顯示：

- Discord 狀態
- Discord 推送次數
- Discord 錯誤
- Discord 通知時間

若推播失敗，先查看 `discord_last_error`，再檢查：

1. `DISCORD_RESERVATION_WEBHOOK_URL` 是否有效。
2. Discord webhook 是否已被刪除。
3. Edge Function secrets 是否設定在正確的 Supabase project。
4. Edge Function logs 是否有 Discord HTTP 或資料庫錯誤。
5. `site_settings` 是否存在 `openingDays` 與 `openingHours`。

更新 secret 後不需要修改或重新部署 GitHub Pages 前端。
