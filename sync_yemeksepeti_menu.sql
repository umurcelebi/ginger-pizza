-- ============================================================================
-- GINGER PIZZA — YEMEKSEPETİ MENÜ, FİYAT VE GÖRSEL SENKRONİZASYONU
-- Supabase SQL Editor üzerinden çalıştırın.
-- ============================================================================

ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS image_url TEXT;

DO $$
DECLARE
    v_rest_id UUID;
    v_cat_imza UUID;
    v_cat_klasik UUID;
    v_cat_gurme UUID;
    v_cat_veg UUID;
    v_cat_yan UUID;
    v_cat_tatli UUID;
    v_item_id UUID;
BEGIN
    SELECT id INTO v_rest_id FROM public.restaurants WHERE slug = 'ginger-pizza' LIMIT 1;
    IF v_rest_id IS NULL THEN
        RAISE EXCEPTION 'ginger-pizza restoran kaydı bulunamadı.';
    END IF;

    SELECT id INTO v_cat_imza FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'imza' LIMIT 1;
    SELECT id INTO v_cat_klasik FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'klasik' LIMIT 1;
    SELECT id INTO v_cat_gurme FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'gurme' LIMIT 1;
    SELECT id INTO v_cat_veg FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'vejetaryen' LIMIT 1;
    SELECT id INTO v_cat_yan FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'yan-urun' LIMIT 1;
    SELECT id INTO v_cat_tatli FROM public.categories WHERE restaurant_id = v_rest_id AND slug = 'tatli-icecek' LIMIT 1;

    -- Eski menü kalemlerini temizle (item_variants ON DELETE CASCADE ile silinir, geçmiş order_items etkilenmez)
    DELETE FROM public.menu_items WHERE restaurant_id = v_rest_id;

    -- 1. Ginger Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Ginger Pizza', 'Mozzarella peyniri, domates sos, dana bacon, karamelize soğan, cheddar sos, bbq sos.', 'İmza Lezzet', 'signature', 'images/menu/ginger-pizza.jpg', TRUE, TRUE, 1)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 600),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 780),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1320);

    -- 2. Ragnar Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Ragnar Pizza', 'Mozzarella peyniri, domates sos, kavurma, hellim peyniri, közlenmiş patlıcan, çeri domates.', 'Şefin Spesiyali', 'signature', 'images/menu/ragnar-pizza.jpg', TRUE, TRUE, 2)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 680),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 860),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1400);

    -- 3. Ayaz Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Ayaz Pizza', 'Mozzarella peyniri, domates sos, Rize kavurma, beyaz soğan, yeşil biber, kültür mantarı, çeri domates.', 'Kavurmalı', 'signature', 'images/menu/ayaz-pizza.jpg', TRUE, TRUE, 3)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 640),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 820),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1360);

    -- 4. Floki Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Floki Pizza', 'Mozzarella peyniri, domates sos, dana bacon, rokfor peyniri, istiridye mantarı.', 'Gurme Seçim', 'signature', 'images/menu/floki-pizza.jpg', TRUE, TRUE, 4)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 620),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 800),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1320);

    -- 5. Kendi Pizzanı Kendin Yarat
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Kendi Pizzanı Kendin Yarat', 'Seçeceğiniz malzemeler ile (dilediğiniz malzemeleri sipariş notunda belirtebilirsiniz).', 'Özel Seçim', 'signature', 'images/menu/kendi-pizzani-yarat.jpg', TRUE, TRUE, 5)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 580),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1240);

    -- 6. Banner Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Banner Pizza', 'Mozzarella peyniri, domates sos, çeri domates, fesleğen sos.', 'Klasik', 'popular', 'images/menu/banner-pizza.jpg', TRUE, TRUE, 6)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 460),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 600),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1080);

    -- 7. Ross Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Ross Pizza', 'Mozzarella peyniri, domates sos, suda misket mozzarella peyniri, çeri domates, fesleğen sos.', 'Misket Mozzarella', 'popular', 'images/menu/ross-pizza.jpg', TRUE, TRUE, 7)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 500),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 640),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1120);

    -- 8. Montana Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Montana Pizza', 'Mozzarella peyniri, domates sos, dana sucuk, kültür mantarı, siyah dilimli zeytin.', 'Popüler', 'popular', 'images/menu/montana-pizza.jpg', TRUE, TRUE, 8)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 9. Wild Bill Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Wild Bill Pizza', 'Mozzarella peyniri, domates sos, fesleğen soslu tavuk, çeri domates, kültür mantarı, fesleğen sos.', 'Fesleğenli Tavuk', 'popular', 'images/menu/wild-bill-pizza.jpg', TRUE, TRUE, 9)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 530),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 700),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1200);

    -- 10. Vega Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Vega Pizza', 'Mozzarella peyniri, domates sos, bbq soslu tavuk, kültür mantarı, kırmızı biber, karamelize soğan, bbq sos.', 'BBQ Tavuk', 'popular', 'images/menu/vega-pizza.jpg', TRUE, TRUE, 10)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 530),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 700),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1200);

    -- 11. Chuck Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Chuck Pizza', 'Mozzarella peyniri, domates sos, nugget parçaları, mısır, cheddar sos, bbq sos.', 'Çıtır Tavuk', 'popular', 'images/menu/chuck-pizza.jpg', TRUE, TRUE, 11)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 530),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 700),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1200);

    -- 12. Bubble Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Bubble Pizza', 'Mozzarella peyniri, domates sos, ton balığı, kırmızı soğan, mısır.', 'Ton Balıklı', 'popular', 'images/menu/bubble-pizza.jpg', TRUE, TRUE, 12)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 530),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 700),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1200);

    -- 13. Switch Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Switch Pizza', 'Mozzarella peyniri, domates sos, fermente dana sucuk, dana sosis, mısır, siyah dilimli zeytin, yeşil biber.', 'Favori', 'gourmet', 'images/menu/switch-pizza.jpg', TRUE, TRUE, 13)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 14. Parker Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Parker Pizza', 'Mozzarella peyniri, domates sos, dana jambon, dana sucuk, dana sosis.', 'Et Sevenler', 'gourmet', 'images/menu/parker-pizza.jpg', TRUE, TRUE, 14)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 15. Hunter Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Hunter Pizza', 'Mozzarella peyniri, domates sos, duble pepperoni.', '2x Pepperoni', 'gourmet', 'images/menu/hunter-pizza.jpg', TRUE, TRUE, 15)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 600),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 760),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1300);

    -- 16. Gordon Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Gordon Pizza', 'Mozzarella peyniri, domates sos, dana sucuk, hellim peyniri.', 'Sucuk & Hellim', 'gourmet', 'images/menu/gordon-pizza.jpg', TRUE, TRUE, 16)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 17. Marla Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Marla Pizza', 'Mozzarella peyniri, domates sos, dana sucuk, jalapeno turşusu, cheddar sos.', 'Jalapeno & Cheddar', 'gourmet', 'images/menu/marla-pizza.jpg', TRUE, TRUE, 17)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 18. Pablo Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Pablo Pizza', 'Mozzarella peyniri, domates sos, dana bacon, jalapeno biber, kırmızı soğan, sriracha sos.', 'Sriracha & Bacon', 'gourmet', 'images/menu/pablo-pizza.jpg', TRUE, TRUE, 18)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 580),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 760),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1280);

    -- 19. Gang Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Gang Pizza', 'Mozzarella peyniri, domates sos, dana sucuk, közlenmiş patlıcan, kırmızı biber, beyaz peynir.', 'Köz Patlıcanlı', 'gourmet', 'images/menu/gang-pizza.jpg', TRUE, TRUE, 19)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 20. Patrick Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Patrick Pizza', 'Mozzarella peyniri, domates sos, dana jambon, kültür mantarı, ananas.', 'Ananaslı', 'gourmet', 'images/menu/patrick-pizza.jpg', TRUE, TRUE, 20)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1120);

    -- 21. Garner Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Garner Pizza', 'Mozzarella peyniri, domates sos, kültür mantarı, kestane mantarı, istiridye mantarı.', '3 Mantarlı', 'veg', 'images/menu/garner-pizza.jpg', TRUE, TRUE, 21)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1160);

    -- 22. Marty Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Marty Pizza', 'Mozzarella peyniri, domates sos, kültür mantarı, siyah dilimli zeytin, mısır, çeri domates, yeşil biber.', 'Vejetaryen', 'veg', 'images/menu/marty-pizza.jpg', TRUE, TRUE, 22)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1160);

    -- 23. Benny Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Benny Pizza', 'Mozzarella peyniri, domates sos, beyaz soğan, kırmızı soğan, karamelize soğan, çıtır soğan, kekik.', '4 Soğanlı', 'veg', 'images/menu/benny-pizza.jpg', TRUE, TRUE, 23)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1080);

    -- 24. Nino Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Nino Pizza', 'Mozzarella peyniri, domates sos, közlenmiş patlıcan, kırmızı biber, siyah dilimli zeytin, kültür mantarı, çeri domates.', 'Köz Sebzeli', 'veg', 'images/menu/nino-pizza.jpg', TRUE, TRUE, 24)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1160);

    -- 25. Legolas Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Legolas Pizza', 'Mozzarella peyniri, domates sos, ıspanak, beyaz peynir, mısır, çeri domates.', 'Ispanaklı', 'veg', 'images/menu/legolas-pizza.jpg', TRUE, TRUE, 25)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1160);

    -- 26. Gorosaurus Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Gorosaurus Pizza', 'Mozzarella peyniri, domates sos, beyaz peynir, siyah dilimli zeytin, yeşil biber, çeri domates.', 'Akdeniz', 'veg', 'images/menu/gorosaurus-pizza.jpg', TRUE, TRUE, 26)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 520),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 660),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1160);

    -- 27. Tyler Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Tyler Pizza', 'Mozzarella peyniri, domates sos, toz parmesan peyniri, rokfor peyniri, suda misket mozzarella peyniri.', '4 Peynirli', 'veg', 'images/menu/tyler-pizza.jpg', TRUE, TRUE, 27)
    RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES
      (v_item_id, 'small', 'Small (24-26 cm)', 560),
      (v_item_id, 'medium', 'Medium (30-32 cm)', 720),
      (v_item_id, 'xlarge', 'Mega / XL (40-42 cm)', 1220);

    -- 28. Fırınlanmış Elma Dilim Patates (300 gr.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Fırınlanmış Elma Dilim Patates (300 gr.)', 'Zeytinyağı ve kaya tuzu ile fırınlanmıştır.', 'Fırından', 'gourmet', NULL, TRUE, FALSE, 280, 28);

    -- 29. Fırınlanmış Baharatlı Elma Dilim Patates (300 gr.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Fırınlanmış Baharatlı Elma Dilim Patates (300 gr.)', 'Zeytinyağı ve kaya tuzu ile fırınlanmıştır. Cajun baharatı ile karıştırılarak servis edilir.', 'Cajun', 'gourmet', NULL, TRUE, FALSE, 300, 29);

    -- 30. Cheddar Soslu Elma Dilim Patates (300 gr.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Cheddar Soslu Elma Dilim Patates (300 gr.)', 'Zeytinyağı ve kaya tuzu ile fırınlanmıştır. Cheddar sos üzerine dökülür.', 'Sıcak Soslu', 'popular', NULL, TRUE, FALSE, 380, 30);

    -- 31. Nugget (12 Adet)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Nugget (12 Adet)', 'Fırınlanmış nugget (12 adet).', 'Fırınlanmış', 'gourmet', NULL, TRUE, FALSE, 320, 31);

    -- 32. Frankfurter Sosis & Elma Dilim Patates (300 gr.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Frankfurter Sosis & Elma Dilim Patates (300 gr.)', 'Fırınlanmış Frankfurter dana sosis, fırınlanmış elma dilim patates (300 gr.).', 'Sosis & Patates', 'gourmet', NULL, TRUE, FALSE, 580, 32);

    -- 33. Frankfurter Sosis & Baharatlı Elma Dilim Patates (300 gr.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Frankfurter Sosis & Baharatlı Elma Dilim Patates (300 gr.)', 'Fırınlanmış Frankfurter dana sosis, fırınlanmış cajun baharatlı elma dilim patates (300 gr.).', 'Cajun Combo', 'gourmet', NULL, TRUE, FALSE, 600, 33);

    -- 34. Frankfurter Sosis & Cheddar Soslu Elma Dilim Patates
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Frankfurter Sosis & Cheddar Soslu Elma Dilim Patates', 'Fırınlanmış Frankfurter sosis ve cheddar soslu fırınlanmış elma dilim patates (300 gr.).', 'Cheddar Combo', 'popular', NULL, TRUE, FALSE, 700, 34);

    -- 35. Sweet Chili Sos
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Sweet Chili Sos', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', 'images/menu/sweet-chili-sos.jpg', TRUE, FALSE, 20, 35);

    -- 36. BBQ Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'BBQ Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', NULL, TRUE, FALSE, 20, 36);

    -- 37. Sarımsaklı Mayonez Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Sarımsaklı Mayonez Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', NULL, TRUE, FALSE, 20, 37);

    -- 38. Ranch Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Ranch Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', NULL, TRUE, FALSE, 20, 38);

    -- 39. Sriracha Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Sriracha Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Acı Sos', 'popular', NULL, TRUE, FALSE, 20, 39);

    -- 40. Sriracha Mayonez Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Sriracha Mayonez Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', NULL, TRUE, FALSE, 20, 40);

    -- 41. Fesleğen Sos (30 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Fesleğen Sos (30 cc.)', 'Paket olarak servis edilmektedir.', 'Sos', 'popular', NULL, TRUE, FALSE, 40, 41);

    -- 42. Cheddar Sos (60 cc.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Cheddar Sos (60 cc.)', 'Paket olarak servis edilmektedir.', 'Büyük Sos', 'popular', NULL, TRUE, FALSE, 80, 42);

    -- 43. Poşet
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Poşet', 'Çevre Kanunu kapsamında plastik poşetlerin 1 TL karşılığında satılması zorunludur.', 'Zorunlu Bedel', 'gourmet', 'images/menu/poset.jpg', TRUE, FALSE, 1, 43);

    -- 44. Sufle
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Sufle', 'Pudra şekeri ile sıcak servis edilir.', 'Tatlı', 'signature', NULL, TRUE, FALSE, 320, 44);

    -- 45. Soda (20 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Soda (20 cl.)', 'Cam şişe.', 'İçecek', 'popular', 'images/menu/soda-20cl.jpg', TRUE, FALSE, 60, 45);

    -- 46. Damla Su (33 cl)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Damla Su (33 cl)', 'Cam şişe.', 'İçecek', 'popular', 'images/menu/damla-su-33cl.jpg', TRUE, FALSE, 60, 46);

    -- 47. Özerhisar Ayran (25 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Özerhisar Ayran (25 cl.)', 'Cam şişe.', 'İçecek', 'popular', NULL, TRUE, FALSE, 100, 47);

    -- 48. Özerhisar Ayran (1 L.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Özerhisar Ayran (1 L.)', 'Cam şişe.', '1 Litre', 'popular', 'images/menu/ozerhisar-ayran-1l.jpg', TRUE, FALSE, 160, 48);

    -- 49. Coca-Cola (33 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Coca-Cola (33 cl.)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 49);

    -- 50. Coca-Cola Zero Sugar (33 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Coca-Cola Zero Sugar (33 cl.)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 50);

    -- 51. Fanta (33 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Fanta (33 cl.)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 51);

    -- 52. Sprite (33 cl.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Sprite (33 cl.)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 52);

    -- 53. Fuse Tea Şeftali (33 cl)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Fuse Tea Şeftali (33 cl)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 53);

    -- 54. Fuse Tea Limon (33 cl)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Fuse Tea Limon (33 cl)', 'Kutu içecek.', 'Kutu İçecek', 'popular', NULL, TRUE, FALSE, 120, 54);

    -- 55. Coca-Cola (1 L.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Coca-Cola (1 L.)', 'Pet şişe.', '1 Litre', 'popular', 'images/menu/coca-cola-1l.jpg', TRUE, FALSE, 160, 55);

    -- 56. Coca-Cola Zero Sugar (1 L.)
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, image_url, is_available, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Coca-Cola Zero Sugar (1 L.)', 'Pet şişe.', '1 Litre', 'popular', 'images/menu/coca-cola-zero-1l.jpg', TRUE, FALSE, 160, 56);

END $$;
