# Phase 2-A Release Checklist

## 部署檔案

- [ ] `.gitignore` 包含 `supabase/.temp/`。
- [ ] 專案與 Git 追蹤內容均不包含 `supabase/.temp/`。
- [ ] Discord webhook URL 未出現在前端或 Git repository。
- [ ] Supabase service role key 未出現在前端或 Git repository。
- [ ] 已在 SQL Editor 執行 `supabase/reservation-release-cleanup.sql`。
- [ ] 已重新部署 `notify-reservation-discord` Edge Function。

## 營業時間

- [ ] 後台網站設定修改 `openingDays` 與 `openingHours`。
- [ ] 送出測試預約。
- [ ] Discord 推播營業時間跟著網站設定變動。
- [ ] 清空 `DISCORD_RESERVATION_BUSINESS_HOURS` 時，仍從 `site_settings` 讀取。
- [ ] 故意讓 `site_settings` 查詢失敗時，使用
      `DISCORD_RESERVATION_BUSINESS_HOURS`。
- [ ] 資料庫查詢失敗且 env 未設定時，使用預設營業時間。

## 日期與權限

- [ ] 在台灣時間凌晨 00:00 至 08:00 測試，首個可預約日期不會差一天。
- [ ] `min_days_before` 以 `Asia/Taipei` 當日起算。
- [ ] anon 無法直接 select `reservations`。
- [ ] anon 無法直接 select `reservation_date_overrides`。
- [ ] anon 可以呼叫 `get_public_reservation_availability()`。
- [ ] RPC 只回傳 `reservation_date`、`display_label`、`available_slots`。
- [ ] 前台只能看到可預約日期與可預約時段。
- [ ] owner / admin 可以管理例外日期。
- [ ] staff 可以查看例外日期，但不能修改。
- [ ] 例外日期的內部 note 不會透過公開 RPC 回傳。

## Discord

- [ ] Discord 推播成功後，狀態、次數與通知時間正確更新。
- [ ] Discord 推播失敗不影響預約成立。
- [ ] 推播失敗時，後台可看到 `discord_last_error`。
- [ ] owner / admin 可以從後台重新推播 Discord。
- [ ] staff 看不到重新推播按鈕。
- [ ] 已刪除預約不會被推播。
