# 點餐 Discord 推播部署

## 安全原則

Discord webhook URL 與 Supabase service role key 都是伺服器端機密，不可放入：

- GitHub Pages 的 HTML 或 JavaScript
- `js/site-config.js`
- `js/supabase-client.js`
- Git repository

前端只使用 Supabase publishable／anon key 呼叫 Edge Function。Edge Function
使用 service role 從資料庫讀取完整訂單並更新 Discord 狀態，不會放寬 anon
對 `orders` 或 `order_items` 的 RLS。

## 設定 secrets

先登入並連結 Supabase project：

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

設定必要 secrets：

```bash
supabase secrets set \
  DISCORD_ORDER_WEBHOOK_URL="https://discord.com/api/webhooks/..." \
  SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY"
```

Windows PowerShell 可分別執行：

```powershell
supabase secrets set DISCORD_ORDER_WEBHOOK_URL="https://discord.com/api/webhooks/..."
supabase secrets set SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co"
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY"
```

確認 secret 名稱：

```bash
supabase secrets list
```

不要把含有真實 secret 的指令保存到 Git、文件或前端程式。Webhook URL 洩漏後，
任何取得網址的人都能向 Discord 頻道發送訊息；service role key 則可繞過 RLS，
因此絕對不能放在瀏覽器端。

## 部署 Edge Function

先在 Supabase SQL Editor 執行：

```text
supabase/order-discord-notify.sql
```

此 SQL 只讓 `service_role` 通過訂單 update 保護 trigger，以便 Edge Function
更新 `discord_attempts`、`discord_status`、`discord_last_error` 與通知時間。
anon、staff 與一般登入者的資料庫權限不會因此放寬。

從專案根目錄執行：

```bash
supabase functions deploy notify-order-discord --no-verify-jwt
```

點餐客人不需要登入，而且新式 `sb_publishable_...` key 本身不是 JWT，因此這支
Function 必須使用 `--no-verify-jwt`，否則請求會在進入 Function 前被平台以
`UNAUTHORIZED_INVALID_JWT_FORMAT` 擋下。

關閉平台 JWT 檢查不代表強制重送沒有權限保護：一般前台只允許 `force = false`，
已推送訂單不會重複推送；後台 `force = true` 仍會在 Function 內驗證
Authorization session，並確認使用者是有效的 owner／admin。

查看紀錄：

```bash
supabase functions logs notify-order-discord
```

## 前台測試

1. 開啟 `order-yado.html` 或 `order-kissa.html`。
2. 送出一筆測試點餐。
3. 前台應顯示「已收到您的點餐，請稍候店員確認。」
4. Discord 應收到「嘿月湯宿｜出餐通知」embed。
5. 在 `orders` 確認：
   - `discord_status = sent`
   - `discord_attempts` 增加 1
   - `discord_notified_at` 有時間
   - `discord_last_error` 為空

Discord 推播失敗不會取消訂單。只有 `submit_order` RPC 本身失敗時，前台才會顯示
點餐失敗。

## 後台重新推送

1. 使用 owner 或 admin 登入 `admin/orders.html`。
2. 找到要重新推送的訂單。
3. 點擊「重新推送 Discord」並完成確認。
4. 成功後列表會重新載入 Discord 狀態。

第一版 staff 不提供重新推送按鈕，Edge Function 也會拒絕 staff 的 `force = true`
請求。已軟刪除訂單不會顯示重送按鈕，Function 收到已刪除訂單時也會略過。

## 失敗排查

後台訂單卡片會顯示：

- Discord 狀態
- Discord 推送次數
- Discord 通知時間
- Discord 錯誤

若推播失敗，先查看 `discord_last_error`，再檢查：

1. `DISCORD_ORDER_WEBHOOK_URL` 是否有效。
2. Discord webhook 是否已被刪除。
3. Edge Function secrets 是否設定在正確的 project。
4. Function logs 是否有 Discord HTTP 或資料庫錯誤。
5. `orders` 與 `order_items` 是否仍可由 service role 查詢。

修正 secret 後不需要重新部署 GitHub Pages；可直接從後台重新推送。
