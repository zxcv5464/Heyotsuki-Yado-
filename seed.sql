-- Run supabase/schema.sql before this file.
-- This seed is idempotent and preserves the current local content.

insert into public.site_settings (key, value, description)
values
  ('siteName', '嘿月湯宿', '網站名稱'),
  ('subtitle', 'HEYOTSUKI YADO', '網站副標題'),
  ('address', '利維坦 白銀鄉 15區7號', '店舖地址'),
  ('openingDays', '週五 至 週日', '營業日'),
  ('openingHours', 'PM 21:00 — 24:00', '營業時間'),
  ('status', '目前休業中', '目前營業狀態'),
  ('bookingUrl', 'https://forms.gle/jB7BiMt7krT9eHKj9', '預約表單網址'),
  ('threadsUrl', 'https://www.threads.com/@heyotsuki_ffxiv', 'Threads 連結'),
  ('discordUrl', 'https://discord.gg/AxDQSmwc8j', 'Discord 連結'),
  ('taglineIndex', '隱沒在白銀山中的神祕湯宿', '首頁頁尾標語'),
  ('taglineDefault', '一個遠離塵囂的都市綠洲', '一般頁面頁尾標語'),
  ('menu.menu.pageTitle', '湯之御品書', '湯宿菜單頁面標題'),
  ('menu.menu.subtitle', 'HEYOTSUKI YADO', '湯宿菜單頁面副標題'),
  ('menu.menu.footer', '["一 湯 映 月 ・ 靜 入 心 宿"]', '湯宿菜單頁尾文案 JSON'),
  ('menu.menu2.pageTitle', '嘿月喫茶', '喫茶菜單頁面標題'),
  ('menu.menu2.subtitle', 'HEYOTSUKI YADO', '喫茶菜單頁面副標題'),
  ('menu.menu2.footer', '["無論是獨自閱讀的午後，還是與摯友的低聲細語，《嘿月喫茶》都為您留了一盞燈。","時間彷彿凝固在那個和洋並蓄、自由奔放的黃金年代。推開沉重的檜木大門，撲面而來的是深色磨砂木質與現磨咖啡交織的沉穩香氣。"]', '喫茶菜單頁尾文案 JSON')
on conflict (key) do update set
  value = excluded.value,
  description = excluded.description,
  updated_at = now();

insert into public.menus (
  key, title, short_title, english_title, description, href, theme,
  is_visible, sort_order
)
values
  ('menu', '湯宿菜單', '湯宿菜單', 'YADO MENU', '溫泉、服務、套餐、茶席', 'menu.html', 'light', true, 10),
  ('menu2', '喫茶菜單', '喫茶菜單', 'KISSA MENU', '茶飲、甜點、輕食', 'menu2.html', 'dark', true, 20)
on conflict (key) do update set
  title = excluded.title,
  short_title = excluded.short_title,
  english_title = excluded.english_title,
  description = excluded.description,
  href = excluded.href,
  theme = excluded.theme,
  is_visible = excluded.is_visible,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.staff_members (
  id, name, subtitle, quote, role, image_url, is_visible, sort_order
)
values
  (md5('staff:1:古嘿嘿')::uuid, '古嘿嘿', '老闆娘 / 毒舌系', '「嘿月湯宿闆娘，惡毒系。平常是喜歡到處拍照的新手攝影師，只想追尋我夢寐以求的光影。」', '老闆娘', 'assets/images/staff/staff-gu-heihei.webp', true, 10),
  (md5('staff:2:芝麻渣渣')::uuid, '芝麻渣渣', '人氣偶像 / 我推的芝麻', '「生活充滿各種情緒，好的壞的都歡迎與我分享，煩惱化作渣渣隨風而散。」', '湯娘', 'assets/images/staff/staff-zhima-zhazha.webp', true, 20),
  (md5('staff:3:澪月 小百合')::uuid, '澪月 小百合', '可愛擔當 / 活潑貓娘', '「我是這裡的可愛擔當 ( 自稱 )，澪月小百合！你可以叫我小百合！或者直接叫我「店裡那隻活蹦亂跳的貓娘」也行喔！」', '湯娘', 'assets/images/staff/staff-miozuki-sayuri.webp', true, 30),
  (md5('staff:4:阿祐')::uuid, '阿祐', '高端攝影 / 調皮攝影師', '「小本經營，請勿那個。」', '攝影師', 'assets/images/staff/staff-ayou.webp', true, 40),
  (md5('staff:5:烏蘭')::uuid, '烏蘭', '面癱系(? / 最愛拉拉肥', '「店內唯一的暮輝龍，雖然會溫柔的接待所有客人，但據說拉拉菲爾族能的到特別溫柔的服務？」<br>「世界上總是會有痛苦難過的事情，但如果本店能讓您感到一點點溫柔的話，世界一定就變得更溫暖了一點。 」', '湯娘', 'assets/images/staff/staff-wulan.webp', true, 50),
  (md5('staff:6:BO堤')::uuid, 'BO堤', '調皮擔當 / 閒步住的卯咪', '「是隻有點調皮、超愛到處亂晃的卯咪。被湯屋闆娘撿回來後，就在這裡打工混日子 （呃，認真幫忙啦）不過如果看到我在偷懶……可以當作沒看到嗎？來這裡放鬆就好，有什麼新鮮趣事也可以跟我分享 喵嗚。」', '月娘 不接受指名', 'assets/images/staff/staff-bodi.webp', true, 60),
  (md5('staff:7:月落夢蒔')::uuid, '月落夢蒔', '店貓 / 容易被拐走', '「喵~(蹭蹭)<br>(看見貓薄荷)(飛撲~<br>(一口叼走<br>吾乃店貓是也，依靠蹭蹭維持貓壽~可以給我一個摸摸嘛~QAQ(蹭蹭)」', '店內吉祥貓', 'assets/images/staff/staff-yueluo-mengshi.webp', true, 70),
  (md5('staff:8:梓凜')::uuid, '梓凜', '電玩少女 / 嘿月吉祥物', '「上班就想下班、只要沒上班就是個天天在家裡打電動的電玩少女，有自信只要妳說的出來80%的電玩遊戲都玩過，祈求過著沒有人指名在嘿月湯宿被闆娘包養的吉祥物。」', '湯娘', 'assets/images/staff/staff-zilin.webp', true, 80),
  (md5('staff:9:千反田')::uuid, '千反田', '好奇貓貓 / 愛吃飯糰', '「一隻對每件事情都充滿好奇心的貓貓，雖然帶著眼鏡看起來很機靈，但有時會有天然呆的一面，無時無刻都想吃飯團，在店裡看到的話要幫忙保密別告訴闆娘！」', '湯娘', 'assets/images/staff/staff-chitanda.webp', true, 90),
  (md5('staff:10:玖玖')::uuid, '玖玖', '天然呆 / 話癆', '「你好哇！我是玖玖，平時會有點呆呆的，但熟了之後很會聊的喔！<br>歡迎大家來這里找玖玖玩～我會努力記住每位客人的！」', '湯娘', 'assets/images/staff/staff-jiujiu.webp', true, 100),
  (md5('staff:11:優幽')::uuid, '優幽', '妖貓女帝/霸氣總喵', '「別隨便靠近本座，除非汝夠資格。」<br>「資格，不是靠嘴說的。」「真正夠資格的人，得有膽量直視本座，得有能耐在所有人低頭時，依舊站得筆直，更得有本事，讓本座記住汝的名字，至少，別讓本座失望，<br>否則汝連離開這裡的資格，都不會剩下。」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-yuyou.webp', true, 110),
  (md5('staff:12:安海瑟薇大力')::uuid, '安海瑟薇大力', '迷因系 / 甜食主義', '「咦？是在跟我說話嗎！？那、那個，您好！不好意思我剛剛在花呆，唔、咬到舌頭了⋯⋯！」<br>生性害羞又容易緊張，不過也是隻愛笑的貓咪。還請多多指教♪」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-anne-hathaway-dali.webp', true, 120),
  (md5('staff:13:夏爾')::uuid, '夏爾', '高冷(僅外表？ /  失魂傻龍', '「（冷冷地撥了一下瀏海，淡紫色雙眸閃耀著微光）……命運已經開始轉動，誰能逃離這場邂逅呢？客倌您好，我是…………呃，不好意思，客倌我剛剛說到哪了？我剛剛在看那隻蝴蝶。」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-charles.webp', true, 130),
  (md5('staff:14:佩佩嘎鳳')::uuid, '佩佩嘎鳳', '高難推坑狂 / 幹話系', '「俗話說得好：台上一分鐘，台下60秒。這裡是一位幹話量超標的龍女，歡迎各位來找我聊天，順便聽聽我那些不一定有用但絕對夠多的幹話。」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-peipei-gafeng.webp', true, 140),
  (md5('staff:15:吐吐司')::uuid, '吐吐司', '邪惡馬鈴薯 / 征服世界', '「拉拉菲爾族是天生邪惡的種族。」某人曾經這樣說過，至少，吐吐司這樣深信著。<br>她會用那如麻糬般Q軟的臉頰俘虜你的心，還會把親手做的小餅乾塞進你嘴裡，害你蛀牙！<br>每位貴客都因她的殘酷手段而渾身顫抖，嗯…至少吐吐司是這樣覺得啦。」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-toast.webp', true, 150),
  (md5('staff:16:Lina')::uuid, 'Lina', '裝忙馬鈴薯 / 社恐小肥', '「一隻有點社恐但又努力想交朋友的可愛小肥肥，聽說只要在這邊上班就可以交到朋友，所以就入職了..(如果看到我在偷摸魚，拜託不要告訴老闆娘)<br>歡迎大家找我玩~<br>雖然有點社恐，<br>但肥肥我會努力的ɵ̷̥̥᷄᎔ɵ̷̥̥᷅ .ᐟ」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-lina.webp', true, 160),
  (md5('staff:17:草莓可麗餅')::uuid, '草莓可麗餅', '社恐貓貓 / 求包養', '「在充滿財富的島嶼拿到了足夠的金錢後就來求闆娘包養的超可愛臭臉貓貓，雖然不太理解他在想什麼...但是可以知道的是他一定在想闆娘好可愛」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-strawberry-crepe.webp', true, 170),
  (md5('staff:18:安琳希爾')::uuid, '安琳希爾', '貓手廚娘 / 請買章魚燒', '「 如果心中有什麼灰撲撲的東西，請把它交給我，讓湯屋洗去你的所有不開心。可以的話請打賞我一個微笑，因為那是這世界上最獨特、最珍貴的事物了。」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-anlin-hill.webp', true, 180),
  (md5('staff:19:傑克')::uuid, '傑克', 'FF貪啃奇 / 馬鈴薯愛好者', '「海都舔舔怪，當湯屋客人當到變成店員，歡迎大家多找我一起拍照尬聊:D」', '攝影師', 'assets/images/staff/staff-jack.webp', true, 190),
  (md5('staff:20:綠tea')::uuid, '綠tea', '喜歡摸摸  / 好想睡覺', '「就只是隻每天都很想睡覺的貓咪,歡迎一起來當個摸摸怪!」', '月娘 不接受指名', 'assets/images/staff/staff-green-tea.webp', true, 200),
  (md5('staff:21:Elicon')::uuid, 'Elicon', '冒失 / 鄰家小妹', '「客人初次見面，可以叫我欸哩控，忙了一天一定很辛苦吧!我們這邊可是有首~區一指的湯喔~希望能為你洗去旅途的疲憊~」<br>「如果有任何不開心，讓我幫你把他趕到九霄雲外來這是給你的茶點」<br>「阿阿~~!!(摔倒)」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-elicon.webp', true, 210),
  (md5('staff:22:吹雪')::uuid, '吹雪', '塔羅 / 貓貓老大', '「是個害羞、偏慢熱的貓貓，喜歡發呆、貓貓以及和大家聊天，也會替客人占卜想知道的事情，歡迎來找我挖掘內心深處的世界！」', '月詠師', 'assets/images/staff/staff-fubuki.webp', true, 220),
  (md5('staff:23:柔夜')::uuid, '柔夜', '大和撫子 / 害羞靦腆', '「客官您好～小女是個非常害羞內向的龍龍>< <br>熟絡之後才比較放開一點～希望客官們多多指教！」', '湯娘實習中 不接受指名', 'assets/images/staff/staff-rouye.webp', true, 230),
  (md5('staff:24:準備中')::uuid, '準備中', '新進湯娘 / 敬啟期待', '「準備中。」', '敬啟期待', 'assets/images/staff/staff-coming-soon.webp', true, 240)
on conflict (id) do update set
  name = excluded.name,
  subtitle = excluded.subtitle,
  quote = excluded.quote,
  role = excluded.role,
  image_url = excluded.image_url,
  is_visible = excluded.is_visible,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.menu_sections (
  id, menu_key, title, subtitle, notice, layout_type, is_visible, sort_order
)
values
  (md5('section:menu:10')::uuid, 'menu', '月下湯語', null, '(僅限2人以下體驗並以人頭計費)', 'detailed', true, 10),
  (md5('section:menu:11')::uuid, 'menu', '追憶祈詠', null, null, 'nested_detailed', true, 11),
  (md5('section:menu:21')::uuid, 'menu', '御膳之味', null, null, 'compact', true, 21),
  (md5('section:menu:31')::uuid, 'menu', '和韻茶席', null, null, 'compact', true, 31),
  (md5('section:menu2:10')::uuid, 'menu2', '銘茶', 'Signature Tea', null, 'detailed', true, 10),
  (md5('section:menu2:20')::uuid, 'menu2', '咖啡', 'Specialty Coffee', null, 'detailed', true, 20),
  (md5('section:menu2:30')::uuid, 'menu2', '洋食', 'Western Cuisine', null, 'detailed', true, 30),
  (md5('section:menu2:40')::uuid, 'menu2', '和菓子', 'Wagashi', null, 'detailed', true, 40)
on conflict (id) do update set
  menu_key = excluded.menu_key,
  title = excluded.title,
  subtitle = excluded.subtitle,
  notice = excluded.notice,
  layout_type = excluded.layout_type,
  is_visible = excluded.is_visible,
  sort_order = excluded.sort_order,
  updated_at = now();

insert into public.menu_items (
  id, section_id, name, description, price, featured, is_visible, sort_order
)
values
  (md5('item:menu:10:1')::uuid, md5('section:menu:10')::uuid, '月影套餐 (大約60分鐘)', '湯浴 × 茶點 × 靜夜時光', '300,000 Gil', false, true, 10),
  (md5('item:menu:10:2')::uuid, md5('section:menu:10')::uuid, '夜月尊享 (單人方案限定)', '雙湯娘的帝王級享受', '+100,000 Gil', false, true, 20),
  (md5('item:menu:11:1')::uuid, md5('section:menu:11')::uuid, '拍立得（簽繪版本 +20,000 Gil）', '留下您與湯娘們的幸福時刻 (部分湯娘無簽繪版本)', '80,000 Gil', false, true, 10),
  (md5('item:menu:11:2')::uuid, md5('section:menu:11')::uuid, '祈願之舞', '祈禱月之神所帶來的祝福之力 (也可以依照自己心意多添香油錢贊助)', '200,000 Gil', false, true, 20),
  (md5('item:menu:11:3')::uuid, md5('section:menu:11')::uuid, '月詠體驗', '由月詠師為您解讀心中所問，以月光為引，傾聽心聲，解讀當下的方向。', '300,000 Gil', false, true, 30),
  (md5('item:menu:21:1')::uuid, md5('section:menu:21')::uuid, '茶碗蒸', null, '12,000 Gil', false, true, 10),
  (md5('item:menu:21:2')::uuid, md5('section:menu:21')::uuid, '散壽司', null, '15,000 Gil', false, true, 20),
  (md5('item:menu:21:3')::uuid, md5('section:menu:21')::uuid, '章魚燒', null, '15,000 Gil', false, true, 30),
  (md5('item:menu:21:4')::uuid, md5('section:menu:21')::uuid, '什錦壽司卷', null, '15,000 Gil', false, true, 40),
  (md5('item:menu:21:5')::uuid, md5('section:menu:21')::uuid, '關東煮', null, '12,000 Gil', false, true, 50),
  (md5('item:menu:21:6')::uuid, md5('section:menu:21')::uuid, '湯娘隱藏版', null, '20,000 Gil', true, true, 60),
  (md5('item:menu:31:1')::uuid, md5('section:menu:31')::uuid, '牛奶', null, '10,000 Gil', false, true, 10),
  (md5('item:menu:31:2')::uuid, md5('section:menu:31')::uuid, '抹茶', null, '10,000 Gil', false, true, 20),
  (md5('item:menu2:10:1')::uuid, md5('section:menu2:10')::uuid, '手沖高山茶', '擷取山間雲霧，一盞澄澈回甘的清幽', '15,000 Gil', false, true, 10),
  (md5('item:menu2:10:2')::uuid, md5('section:menu2:10')::uuid, '經典抹茶', '碧色茶湯中的石磨餘韻，品味純粹的和式禪意', '15,000 Gil', false, true, 20),
  (md5('item:menu2:10:3')::uuid, md5('section:menu2:10')::uuid, '仙子莓茶', '森林漿果的微酸華爾滋，編織紅寶石色的夢幻', '15,000 Gil', false, true, 30),
  (md5('item:menu2:20:1')::uuid, md5('section:menu2:20')::uuid, '鮮奶油咖啡', '琥珀色深焙與雪白鮮奶油，交織出苦甜參半的優雅', '18,000 Gil', false, true, 10),
  (md5('item:menu2:20:2')::uuid, md5('section:menu2:20')::uuid, '奶泡奶油肉桂咖啡', '辛香肉桂揉入絲滑奶泡，冬日暖陽般的濃郁治癒', '20,000 Gil', false, true, 20),
  (md5('item:menu2:30:1')::uuid, md5('section:menu2:30')::uuid, '手作蛋包飯', '金黃滑嫩的蛋皮包覆，重現昭和年代的純樸溫度', '25,000 Gil', false, true, 10),
  (md5('item:menu2:30:2')::uuid, md5('section:menu2:30')::uuid, '起司焗洋蔥湯', '慢火焦糖化的洋蔥精華，與拉絲起司的醇厚共舞', '25,000 Gil', false, true, 20),
  (md5('item:menu2:40:1')::uuid, md5('section:menu2:40')::uuid, '金平糖', '掌心裡的星辰碎片，清脆封存了童年的甜蜜記憶', '10,000 Gil', false, true, 10),
  (md5('item:menu2:40:2')::uuid, md5('section:menu2:40')::uuid, '乳酪甜甜圈', '濃郁乳酪與鬆軟麵芯，鹹甜之間演繹的午茶浪漫', '10,000 Gil', false, true, 20)
on conflict (id) do update set
  section_id = excluded.section_id,
  name = excluded.name,
  description = excluded.description,
  price = excluded.price,
  featured = excluded.featured,
  is_visible = excluded.is_visible,
  sort_order = excluded.sort_order,
  updated_at = now();
