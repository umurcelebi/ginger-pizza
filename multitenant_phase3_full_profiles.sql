-- ==============================================================================
-- XUBO / GINGER PIZZA - PLAN C: TAM VERİ ODAKLI RESTORAN PROFİLLERİ
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- we-smash-the-burger ve ginger-pizza için tam vitrin profil verilerini
-- restaurants.profile (JSONB) sütununa taşır.
-- ==============================================================================

UPDATE public.restaurants
SET
  profile = COALESCE(profile, '{}'::jsonb) || jsonb_build_object(
    'logo_url', 'images/we-smash-logo.jpg',
    'hero_tag', 'Bahçelievler''in İmza Smash Burgeri',
    'hero_title_html', 'Gerçek smash,<br>sıcak ızgara,<br><span class="highlight">We Smash</span> lezzeti.',
    'hero_desc', 'Günlük taze dana kıyması, yüksek ısıda mühürlenmiş çıtır kenarlı smash köfteler ve özel soslar. Bahçelievler''in imza smash burger deneyimi.',
    'featured', jsonb_build_object(
      'image', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/76850501-950a-4301-bc42-c2ebca4ddaa0.jpg?width=600&height=600',
      'name', 'Houston Burger',
      'desc', '2 adet 70 gr. smash köfte, 2x cheddar, ıceberg, turşu & burger sos',
      'pill', '70 / 140 / 210 gr.'
    ),
    'story_title', 'İyi smash burger aceleye gelmez.',
    'story_desc', 'Bahçelievler Deli Hüseyin Paşa Caddesi''ndeki mutfağımızda her gün aynı tutkuyla hazırlanıyoruz. İyi bir smash burgerin sırrı; taze ette, doğru ısıda ve dengeli soslarda gizlidir.',
    'craft_cards', jsonb_build_array(
      jsonb_build_object('title', 'Gramajına Göre Smash Köfte', 'text', '70 gr. tekli, 140 gr. double ve 210 gr. triple köfte gramajlarıyla damak tadınıza göre porsiyon seçin.'),
      jsonb_build_object('title', 'Yüksek Isıda Izgara', 'text', 'Özel smash presi ile ızgarada saniyeler içinde mühürlenen köfteler dışı çıtır, içi sulu kalır.'),
      jsonb_build_object('title', 'Özel Soslar & Peynirler', 'text', 'Cheddar, kaşar ve Erzincan tulum peynirleri; trüflü mayonez, barbekü, jalapeno salsa ve burger sosla buluşur.')
    ),
    'menu_desc', 'Her biri sipariş anında sıcak ızgarada hazırlanan smash burger menüler, burgerler ve eşlikçiler.',
    'search_placeholder', 'Burger, menü veya sos ara (örn: houston, texas...)',
    'hub_banner_eyebrow', 'En Hızlı & Doğrudan Izgaradan',
    'hub_banner_desc', 'Menüden burgerinizi ve gramajınızı seçin, sepetinize ekleyin; mutfağımız anında hazırlasın ve canlı olarak takip edin.',
    'hub_cta_label', '🍔 Menüden Seç',
    'contact_title', 'Bahçelievler''de Sıcak Bir Burger Molası',
    'contact_desc', 'Bahçelievler''de ızgaradan yeni çıkmış smash burgerlerimizle sizleri ağırlamaktan mutluluk duyuyoruz.',
    'hours_html', 'Haftanın her günü:<br>12:00 – 03:45 (Paket Servis &amp; Gel Al)',
    'footer_tagline', 'Bahçelievler''in imza smash burger noktası. Taze dana eti, sıcak ızgara ve özel soslar.',
    'footer_city', 'Bahçelievler / İstanbul',
    'footer_meta', 'Bahçelievler, İstanbul · Smash Burger',
    'coming_eyebrow', '🔥 Izgaramız Sıcak, Sitemiz Hazırlanıyor',
    'coming_title_html', 'Yeni smash burger menümüz ve online sipariş sistemimiz <em>çok yakında</em> burada.',
    'coming_desc', 'Bahçelievler''deki mutfağımızdan sıcacık smash burgerlerimizi doğrudan web sitemiz üzerinden sipariş edebilmeniz için son hazırlıklarımızı yapıyoruz. Bu sırada telefonla hemen sipariş verebilirsiniz.',
    'coming_hours_html', 'Haftanın her günü: 12:00 – 03:45<span class="info-sub">Paket Servis &amp; Gel Al</span>'
  ),
  updated_at = NOW()
WHERE slug = 'we-smash-the-burger';
