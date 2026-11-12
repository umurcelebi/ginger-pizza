-- We Smash The Burger — Yemeksepeti Menü, Görsel, Ödeme Tipleri & Çalışma Saatleri Seed
-- Supabase Dashboard → SQL Editor üzerinde bir kez çalıştırınız.

DO $$
DECLARE
  v_rest_id UUID;
  v_cat_menuler UUID;
  v_cat_burgerler UUID;
  v_cat_yan UUID;
  v_cat_icecek UUID;
  v_cat_soslar UUID;
  v_cat_poset UUID;
BEGIN
  SELECT id INTO v_rest_id
  FROM public.restaurants
  WHERE slug = 'we-smash-the-burger'
  LIMIT 1;

  IF v_rest_id IS NULL THEN
    RAISE EXCEPTION 'we-smash-the-burger restoran kaydı bulunamadı!';
  END IF;

  -- 1. Restoran adresi güncelleme
  UPDATE public.restaurants
  SET
    address = 'Deli Hüseyin Paşa Caddesi 36/B Ejder Apartmanı, Bahçelievler / İstanbul',
    updated_at = NOW()
  WHERE id = v_rest_id;

  -- 2. Çalışma saatleri (Her gün 12:00 - 03:45) ve Ödeme Tipleri
  INSERT INTO public.store_settings (
    id, order_mode, busy_until, status_message, weekly_hours,
    online_discount_enabled, online_discount_percent, payment_methods, updated_at
  )
  VALUES (
    'we-smash-the-burger',
    'auto',
    NULL,
    '',
    '{
      "0": {"enabled": true, "open": "12:00", "close": "03:45"},
      "1": {"enabled": true, "open": "12:00", "close": "03:45"},
      "2": {"enabled": true, "open": "12:00", "close": "03:45"},
      "3": {"enabled": true, "open": "12:00", "close": "03:45"},
      "4": {"enabled": true, "open": "12:00", "close": "03:45"},
      "5": {"enabled": true, "open": "12:00", "close": "03:45"},
      "6": {"enabled": true, "open": "12:00", "close": "03:45"}
    }'::jsonb,
    false,
    0,
    '[
      {"id": "door_card", "label": "Kapıda Kredi Kartı", "icon": "💳", "enabled": true, "isDefault": true},
      {"id": "door_cash", "label": "Nakit", "icon": "💵", "enabled": true, "isDefault": true},
      {"id": "online_card", "label": "Online Kredi Kartı / Banka Kartı", "icon": "🌐", "enabled": true, "isDefault": false},
      {"id": "iyzico", "label": "iyzico ile Öde", "icon": "🛡️", "enabled": true, "isDefault": false},
      {"id": "wallet", "label": "Cüzdan", "icon": "👛", "enabled": true, "isDefault": false}
    ]'::jsonb,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    weekly_hours = EXCLUDED.weekly_hours,
    payment_methods = EXCLUDED.payment_methods,
    updated_at = NOW();

  -- 3. Mevcut menü ve kategorileri temizle (sadece we-smash-the-burger için)
  DELETE FROM public.menu_items WHERE restaurant_id = v_rest_id;
  DELETE FROM public.categories WHERE restaurant_id = v_rest_id;

  -- 4. Kategorileri ekle
  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'Burger Menüler', 'burger-menuler', 1) RETURNING id INTO v_cat_menuler;

  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'Burgerler', 'burgerler', 2) RETURNING id INTO v_cat_burgerler;

  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'Yan Ürünler', 'yan-urunler', 3) RETURNING id INTO v_cat_yan;

  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'İçecekler', 'icecekler', 4) RETURNING id INTO v_cat_icecek;

  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'Soslar', 'soslar', 5) RETURNING id INTO v_cat_soslar;

  INSERT INTO public.categories (restaurant_id, name, slug, sort_order)
  VALUES (v_rest_id, 'Poşet', 'poset', 6) RETURNING id INTO v_cat_poset;

  -- 5. Tüm ürünleri ekle (39 ürün)
  INSERT INTO public.menu_items (
    restaurant_id, category_id, name, description, badge, badge_type,
    image_url, is_available, is_pizza, fixed_price, sort_order, modifiers
  ) VALUES
  -- Burger Menüler
  (v_rest_id, v_cat_menuler, 'Jr. Oklahoma Burger Menü', 'Oklahoma Burger (70 gr. smash burger köftesi, soğan, cheddar peyniri) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/82a23ff2-ec90-487b-9e67-dd6e988fe7e1.jpg?width=128&height=128', true, false, 500, 1, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Jr. Cheeseburger Menü', 'Cheeseburger (70 gr. smash burger köftesi, cheddar peyniri, soğan, kornişon turşu, ketçap, hardal sos) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/7b2a9d48-b483-4c05-b0d5-750212af93fb.jpg?width=128&height=128', true, false, 515, 2, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Jr. Klasik Burger Menü', 'Klasik Burger (70 gr. smash burger köftesi, soğan, kornişon turşu, ketçap, hardal sos) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/2f0f630a-6a12-4a6f-b3d6-8e735c42d5ba.jpg?width=300&height=300', true, false, 500, 3, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Houston Burger Menü', 'Houston Burger 140 GR (2 adet 70 gr. smash burger köftesi, 2 adet cheddar peyniri, ıceberg, kornişon turşu, burger sos) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/76850501-950a-4301-bc42-c2ebca4ddaa0.jpg?width=300&height=300', true, false, 715, 4, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Denver Burger Menü', 'Denver Burger 140GR (2 adet 70 gr. smash burger köftesi, 2 adet kaşar peyniri, çıtır soğan, mantar sote, trüflü mayonez) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/8c6cc429-76dc-47e1-8788-e791f175193b.jpg?width=300&height=300', true, false, 715, 5, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Texas Burger Menü', 'Texas Burger 140GR (2 adet 70 gr. smash burger köftesi, 2 adet cheddar peyniri, füme et, çıtır soğan, barbekü sos) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/ae208147-e1e2-4816-8f11-121345056f83.jpg?width=300&height=300', true, false, 730, 6, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Atlanta Burger Menü', 'Atlanta Burger 140GR (2 adet 70 gr. smash burger köftesi, Erzincan tulum peyniri, vişne mermelat) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/70297bcf-188e-4113-801e-166b809c9c55.jpg?width=300&height=300', true, false, 715, 7, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Arizona Burger Menü', 'Arizona Burger 140GR (2 adet 70 gr. smash burger köftesi, cheddar peyniri, kaşar peyniri, çıtır soğan, közlenmiş biber, jalapeno salsa sos) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/52649a2d-3c81-42cd-9145-4e109277c6ac.jpg?width=300&height=300', true, false, 715, 8, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_menuler, 'Washington, DC Burger Menü', 'Washington DC Burger 210 GR (3 adet 70 gr. smash burger köftesi, 3 adet cheddar peyniri, soğan, kornişon turşu, ketçap, hardal) + Patates Kızartması + Coca-Cola (33 cl.)', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/105a8004-e8ea-4bdf-8004-0c8c010fa058.jpg?width=300&height=300', true, false, 865, 9, '{"removals":[],"additions":[]}'::jsonb),

  -- Burgerler
  (v_rest_id, v_cat_burgerler, 'Jr. Oklahoma Burger', '70 gr. smash burger köftesi, soğan, cheddar peyniri', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663547/eaea580e-7f98-4fca-9879-618c2d290fc0.jpg?width=300&height=300', true, false, 315, 10, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Jr. Klasik Burger', '70 gr. smash burger köftesi, soğan, kornişon turşu, ketçap, hardal', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663583/fff61b4b-4c35-430d-9408-dd97b79ad1fc.jpg?width=300&height=300', true, false, 315, 11, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Jr. Cheeseburger', '70 gr. smash burger köftesi, cheddar peyniri, soğan, kornişon turşu, ketçap, hardal', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663568/fa3a76e1-2acc-418e-861f-3cfe92d06665.jpg?width=300&height=300', true, false, 330, 12, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Houston Burger', '(140GR) 2 adet 70 gr. smash burger köftesi, 2 adet cheddar peyniri, ıceberg, kornişon turşu, burger sos', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663614/1a3d4401-e823-4f22-a46b-3d8c65d8306d.jpg?width=300&height=300', true, false, 530, 13, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Denver Burger', '(140GR) 2 adet 70 gr. smash burger köftesi, 2 adet kaşar peyniri, çıtır soğan, mantar sote, trüflü mayonez', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663638/13ab7b8a-94da-4e51-b636-6fe807db9a7f.jpg?width=300&height=300', true, false, 530, 14, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Texas Burger', '(140GR) 2 adet 70 gr. smash burger köftesi, 2 adet cheddar peyniri, füme et, çıtır soğan, barbekü sos', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663654/0d1bcf65-9df6-4864-9a15-a7d407e4c783.jpg?width=300&height=300', true, false, 545, 15, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Atlanta Burger', '(140GR) 2 adet 70 gr. smash burger köftesi, Erzincan tulum peyniri, vişne mermelat', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663729/bb80490b-38bc-4911-b246-b24e8677dedc.jpg?width=300&height=300', true, false, 530, 16, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Arizona Burger', '(140GR) 2 adet 70 gr. smash burger köftesi, cheddar peyniri, kaşar peyniri, çıtır soğan, közlenmiş biber, jalapeno salsa sos', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/75663791/8aa863c0-ccac-4a9f-b408-762c9030f6bb.jpg?width=300&height=300', true, false, 530, 17, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_burgerler, 'Washington, DC Burger', '(210GR) 3 adet 70 gr. smash burger köftesi, 3 adet cheddar peyniri, soğan, kornişon turşu, ketçap, hardal', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/77918287/d35905b7-8b84-41a9-bd6b-e601b46a939d.jpg?width=300&height=300', true, false, 680, 18, '{"removals":[],"additions":[]}'::jsonb),

  -- Yan Ürünler
  (v_rest_id, v_cat_yan, 'Patates Kızartması', 'Parmak dilim', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289786.jpg?width=300&height=300', true, false, 170, 19, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_yan, 'Baharatlı Patates Kızartması', 'Parmak dilim', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289789.jpg?width=300&height=300', true, false, 175, 20, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_yan, 'Soğan Halkası (6 Adet)', '6 adet olarak servis edilir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/69998569.jpg?width=300&height=300', true, false, 168, 21, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_yan, 'Çıtır Tavuk (200 gr.)', '200 gr. olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/70002448.jpg?width=300&height=300', true, false, 320, 22, '{"removals":[],"additions":[]}'::jsonb),

  -- İçecekler
  (v_rest_id, v_cat_icecek, 'Coca-Cola Şekersiz (33 cl.)', 'Kutu içecek', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289868.jpg?width=300&height=300', true, false, 110, 23, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Coca-Cola (33 cl.)', 'Kutu içecek', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289861.jpg?width=300&height=300', true, false, 110, 24, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Fanta (33 cl.)', 'Kutu içecek', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289872.jpg?width=300&height=300', true, false, 110, 25, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Sprite (33 cl.)', 'Kutu içecek', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289874.jpg?width=300&height=300', true, false, 110, 26, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Ayran (30 cl.)', 'Büyük boy', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289886.jpg?width=300&height=300', true, false, 70, 27, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Su (50 cl.)', 'Pet şişe', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289881.jpg?width=300&height=300', true, false, 35, 28, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_icecek, 'Fuse Tea (33 cl.)', 'Kutu içecek', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/69439046.jpg?width=300&height=300', true, false, 110, 29, '{"removals":[],"additions":[]}'::jsonb),

  -- Soslar
  (v_rest_id, v_cat_soslar, 'Burger Sos', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/products/67289812.jpg?width=300&height=300', true, false, 32, 30, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Ranch Sos', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289814.jpg?width=300&height=300', true, false, 32, 31, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Sarımsaklı Mayonez', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/products/67289815.jpg?width=300&height=300', true, false, 32, 32, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Sriracha Mayonez', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/products/67289828.jpg?width=300&height=300', true, false, 32, 33, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Barbekü Sos', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/products/67289835.jpg?width=300&height=300', true, false, 32, 34, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Acı Sos', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289849.jpg?width=300&height=300', true, false, 32, 35, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Ketçap', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289858.jpg?width=300&height=300', true, false, 16, 36, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Mayonez', 'Adet olarak servis edilmektedir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/Products/67289860.jpg?width=300&height=300', true, false, 16, 37, '{"removals":[],"additions":[]}'::jsonb),
  (v_rest_id, v_cat_soslar, 'Trüflü Mayonez', 'Adet olarak servis edilmektedir.', '', 'popular', '', true, false, 32, 38, '{"removals":[],"additions":[]}'::jsonb),

  -- Poşet
  (v_rest_id, v_cat_poset, 'Poşet', 'Çevre Kanunu kapsamında plastik poşet 1 TL olarak ücretlendirilir.', '', 'popular', 'https://yemeksepeti.dhmedia.io/image/fd-tr/products/67289900.jpg?width=300&height=300', true, false, 1, 39, '{"removals":[],"additions":[]}'::jsonb);
END $$;
