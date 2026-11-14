-- ==============================================================================
-- XUBO / GINGER PIZZA - FAZ 9: YIKICI VE PLATFORMA AİT RPC'LERİN SADECE
-- SUPER_ADMIN İLE SINIRLANDIRILMASI (MAĞAZA YÖNETİCİSİ YETKİ DARALTMASI)
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Ne yapar:
--   1. reset_restaurant_history(p_restaurant_slug):
--      Geçmiş satışların ve müşteri kayıtlarının silinmesini YALNIZCA super_admin
--      yetkisine kapatır (mağaza yöneticisi ciro ve sipariş geçmişini silemez).
--   2. clone_restaurant_menu(p_source_slug, p_target_slug, p_replace_existing):
--      Şablon veya mağazadan mağazaya menü kopyalama / mevcut menüyü üzerine yazma
--      işlemini YALNIZCA super_admin yetkisine kapatır.
-- ==============================================================================

-- 1. reset_restaurant_history() — Yalnızca super_admin çalıştırabilir
CREATE OR REPLACE FUNCTION public.reset_restaurant_history(
  p_restaurant_slug TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := NULLIF(LOWER(TRIM(COALESCE(p_restaurant_slug, ''))), '');
  v_deleted_order_items INTEGER := 0;
  v_deleted_orders INTEGER := 0;
  v_deleted_customers INTEGER := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Geçmiş satışları ve müşterileri yalnızca Platform Yöneticisi (super_admin) sıfırlayabilir.';
  END IF;

  IF v_slug IS NULL THEN
    RAISE EXCEPTION 'INVALID_SLUG: Restoran slug belirtilmelidir.';
  END IF;

  DELETE FROM public.order_items oi
  USING public.orders o
  WHERE oi.order_id = o.id
    AND o.restaurant_slug = v_slug;
  GET DIAGNOSTICS v_deleted_order_items = ROW_COUNT;

  DELETE FROM public.orders o
  WHERE o.restaurant_slug = v_slug;
  GET DIAGNOSTICS v_deleted_orders = ROW_COUNT;

  DELETE FROM public.customers c
  WHERE c.restaurant_slug = v_slug;
  GET DIAGNOSTICS v_deleted_customers = ROW_COUNT;

  RETURN jsonb_build_object(
    'restaurant_slug', v_slug,
    'deleted_order_items', v_deleted_order_items,
    'deleted_orders', v_deleted_orders,
    'deleted_customers', v_deleted_customers
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reset_restaurant_history(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_restaurant_history(TEXT) TO authenticated;


-- 2. clone_restaurant_menu() — Yalnızca super_admin çalıştırabilir
CREATE OR REPLACE FUNCTION public.clone_restaurant_menu(
  p_source_slug TEXT,
  p_target_slug TEXT,
  p_replace_existing BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source_slug TEXT := LOWER(TRIM(COALESCE(p_source_slug, '')));
  v_target_slug TEXT := LOWER(TRIM(COALESCE(p_target_slug, '')));
  v_target_rest RECORD;
  v_source_rest RECORD;
  v_cat RECORD;
  v_new_cat_id UUID;
  v_item RECORD;
  v_new_item_id UUID;
  v_copied_cats INT := 0;
  v_copied_items INT := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Şablon veya mağazadan menü kopyalama işlemini yalnızca Platform Yöneticisi (super_admin) yapabilir.';
  END IF;

  IF v_target_slug = '' OR v_source_slug = '' THEN
    RAISE EXCEPTION 'INVALID_SLUG: Kaynak ve hedef mağaza bilgisi zorunludur.';
  END IF;

  IF v_target_slug = v_source_slug THEN
    RAISE EXCEPTION 'INVALID_TARGET: Kaynak ve hedef mağaza aynı olamaz.';
  END IF;

  SELECT id, slug, name INTO v_target_rest
  FROM public.restaurants
  WHERE slug = v_target_slug
  LIMIT 1;

  IF v_target_rest.id IS NULL THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND: Hedef mağaza bulunamadı (%).', v_target_slug;
  END IF;

  IF v_target_slug = 'ginger-pizza' AND p_replace_existing THEN
    RAISE EXCEPTION 'FORBIDDEN_TARGET: Ana referans mağazanın (ginger-pizza) menüsü üzerine yazılamaz.';
  END IF;

  IF p_replace_existing THEN
    DELETE FROM public.item_variants iv
    USING public.menu_items mi
    WHERE iv.item_id = mi.id
      AND mi.restaurant_id = v_target_rest.id;

    DELETE FROM public.menu_items WHERE restaurant_id = v_target_rest.id;
    DELETE FROM public.categories WHERE restaurant_id = v_target_rest.id;
  END IF;

  -- Hazır Burger Şablonu
  IF v_source_slug = '__template_burger__' THEN
    INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
    VALUES
      (v_target_rest.id, 'smash-burgerler', 'Smash Burgerler', 1),
      (v_target_rest.id, 'tavuk-burgerler', 'Tavuk Burgerler', 2),
      (v_target_rest.id, 'atistirmaliklar', 'Atıştırmalık & Patates', 3),
      (v_target_rest.id, 'icecekler', 'İçecekler', 4)
    ON CONFLICT (restaurant_id, slug) DO NOTHING;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'smash-burgerler' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Classic Smash Burger', 'Çift kat karamelize smash köfte, cheddar peyniri, karamelize soğan, turşu ve özel sos.', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=80', FALSE, 290, TRUE, 1, '{"removals":["Soğan","Turşu","Özel Sos"],"additions":[{"name":"Ekstra Köfte","price":95},{"name":"Ekstra Cheddar","price":30},{"name":"Dana Bacon","price":55}]}'::jsonb),
        (v_target_rest.id, v_new_cat_id, 'Truffle Mushroom Smash', 'Çift kat smash köfte, trüflü mayonez, sote kültür mantarı ve eritilmiş cheddar.', 'https://images.unsplash.com/photo-1586190848861-99aa4a171e90?auto=format&fit=crop&w=800&q=80', FALSE, 330, TRUE, 2, '{"removals":["Mantar","Trüf Sos"],"additions":[{"name":"Ekstra Köfte","price":95},{"name":"Ekstra Cheddar","price":30}]}'::jsonb);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'tavuk-burgerler' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Crispy Chicken Burger', 'Çıtır paneli tavuk göğsü, coleslaw salata, turşu ve ballı hardal sos.', 'https://images.unsplash.com/photo-1606755962773-d324e0a13086?auto=format&fit=crop&w=800&q=80', FALSE, 260, TRUE, 1, '{"removals":["Coleslaw","Turşu"],"additions":[{"name":"Ekstra Cheddar","price":30}]}'::jsonb);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'atistirmaliklar' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Baharatlı Kajun Patates', 'Özel kajun baharatlı çıtır patates kızartması.', 'https://images.unsplash.com/photo-1576107232684-1279f3908594?auto=format&fit=crop&w=800&q=80', FALSE, 110, TRUE, 1),
        (v_target_rest.id, v_new_cat_id, 'Çıtır Soğan Halkası (8''li)', 'Altın sarısı kızarmış çıtır soğan halkaları, barbekü sos ile.', 'https://images.unsplash.com/photo-1639024471283-03518883512d?auto=format&fit=crop&w=800&q=80', FALSE, 105, TRUE, 2);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'icecekler' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Kutu İçecek (330 ml)', 'Soğuk kutu meşrubat seçimi.', 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=800&q=80', FALSE, 65, TRUE, 1),
        (v_target_rest.id, v_new_cat_id, 'Ayran (300 ml)', 'Bol köpüklü soğuk ayran.', 'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=800&q=80', FALSE, 50, TRUE, 2);
    END IF;

    RETURN jsonb_build_object(
      'success', TRUE,
      'source_slug', v_source_slug,
      'target_slug', v_target_slug,
      'copied_categories', 4,
      'copied_items', 7
    );
  END IF;

  -- Hazır Pizza Şablonu
  IF v_source_slug = '__template_pizza__' THEN
    INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
    VALUES
      (v_target_rest.id, 'klasik-pizzalar', 'Klasik Pizzalar', 1),
      (v_target_rest.id, 'gurme-pizzalar', 'Gurme Pizzalar', 2),
      (v_target_rest.id, 'yan-urunler', 'Yan Ürünler & Salata', 3),
      (v_target_rest.id, 'icecekler', 'İçecekler & Tatlılar', 4)
    ON CONFLICT (restaurant_id, slug) DO NOTHING;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'klasik-pizzalar' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers)
      VALUES (
        v_target_rest.id, v_new_cat_id, 'Margherita Pizza',
        'İtalyan domates sosu, taze mozzarella peyniri, fesleğen yaprakları ve sızma zeytinyağı.',
        'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=800&q=80',
        TRUE, NULL, TRUE, 1,
        '{"removals":["Fesleğen"],"additions":[{"name":"Ekstra Mozzarella","price":45,"prices":{"small":35,"medium":45,"large":55}},{"name":"Mantar","price":35,"prices":{"small":25,"medium":35,"large":45}}]}'::jsonb
      ) RETURNING id INTO v_new_item_id;

      INSERT INTO public.item_variants (item_id, size_key, size_label, price)
      VALUES
        (v_new_item_id, 'small', 'Küçük (24 cm)', 240),
        (v_new_item_id, 'medium', 'Orta (30 cm)', 290),
        (v_new_item_id, 'large', 'Büyük (34 cm)', 340);

      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers)
      VALUES (
        v_target_rest.id, v_new_cat_id, 'Pepperoni / Sucuklu Pizza',
        'Domates sos, mozzarella peyniri ve bol dilimlenmiş dana sucuk / pepperoni.',
        'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=800&q=80',
        TRUE, NULL, TRUE, 2,
        '{"removals":["Sucuk"],"additions":[{"name":"Ekstra Mozzarella","price":45,"prices":{"small":35,"medium":45,"large":55}},{"name":"Jalapeno","price":30,"prices":{"small":25,"medium":30,"large":40}}]}'::jsonb
      ) RETURNING id INTO v_new_item_id;

      INSERT INTO public.item_variants (item_id, size_key, size_label, price)
      VALUES
        (v_new_item_id, 'small', 'Küçük (24 cm)', 270),
        (v_new_item_id, 'medium', 'Orta (30 cm)', 330),
        (v_new_item_id, 'large', 'Büyük (34 cm)', 390);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'gurme-pizzalar' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers)
      VALUES (
        v_target_rest.id, v_new_cat_id, 'Dört Peynirli (Quattro Formaggi)',
        'Mozzarella, rokfor, parmesan ve cheddar peynirlerinin taş fırın uyumu.',
        'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=80',
        TRUE, NULL, TRUE, 1,
        '{"removals":["Rokfor"],"additions":[{"name":"Ceviz","price":40,"prices":{"small":30,"medium":40,"large":50}}]}'::jsonb
      ) RETURNING id INTO v_new_item_id;

      INSERT INTO public.item_variants (item_id, size_key, size_label, price)
      VALUES
        (v_new_item_id, 'small', 'Küçük (24 cm)', 285),
        (v_new_item_id, 'medium', 'Orta (30 cm)', 345),
        (v_new_item_id, 'large', 'Büyük (34 cm)', 405);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'yan-urunler' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Fırın Patates', 'Baharatlı elma dilim fırın patates.', 'https://images.unsplash.com/photo-1576107232684-1279f3908594?auto=format&fit=crop&w=800&q=80', FALSE, 110, TRUE, 1);
    END IF;

    SELECT id INTO v_new_cat_id FROM public.categories WHERE restaurant_id = v_target_rest.id AND slug = 'icecekler' LIMIT 1;
    IF v_new_cat_id IS NOT NULL THEN
      INSERT INTO public.menu_items (restaurant_id, category_id, name, description, image_url, is_pizza, fixed_price, is_available, sort_order)
      VALUES
        (v_target_rest.id, v_new_cat_id, 'Kutu İçecek (330 ml)', 'Soğuk kutu meşrubat.', 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=800&q=80', FALSE, 65, TRUE, 1);
    END IF;

    RETURN jsonb_build_object(
      'success', TRUE,
      'source_slug', v_source_slug,
      'target_slug', v_target_slug,
      'copied_categories', 4,
      'copied_items', 5
    );
  END IF;

  -- Mevcut bir mağazanın menüsünü birebir kopyala
  SELECT id, slug, name INTO v_source_rest
  FROM public.restaurants
  WHERE slug = v_source_slug
  LIMIT 1;

  IF v_source_rest.id IS NULL THEN
    RAISE EXCEPTION 'SOURCE_NOT_FOUND: Kaynak mağaza bulunamadı (%).', v_source_slug;
  END IF;

  FOR v_cat IN
    SELECT id, slug, name, sort_order
    FROM public.categories
    WHERE restaurant_id = v_source_rest.id
    ORDER BY sort_order ASC, created_at ASC
  LOOP
    SELECT id INTO v_new_cat_id
    FROM public.categories
    WHERE restaurant_id = v_target_rest.id
      AND slug = v_cat.slug
    LIMIT 1;

    IF v_new_cat_id IS NULL THEN
      INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
      VALUES (v_target_rest.id, v_cat.slug, v_cat.name, v_cat.sort_order)
      RETURNING id INTO v_new_cat_id;
      v_copied_cats := v_copied_cats + 1;
    END IF;

    FOR v_item IN
      SELECT id, name, description, badge, image_url, is_pizza, fixed_price, is_available, sort_order, modifiers
      FROM public.menu_items
      WHERE restaurant_id = v_source_rest.id
        AND category_id = v_cat.id
      ORDER BY sort_order ASC, created_at ASC
    LOOP
      INSERT INTO public.menu_items (
        restaurant_id, category_id, name, description, badge,
        image_url, is_pizza, fixed_price, is_available, sort_order, modifiers
      ) VALUES (
        v_target_rest.id, v_new_cat_id, v_item.name, v_item.description, v_item.badge,
        v_item.image_url, v_item.is_pizza, v_item.fixed_price, v_item.is_available,
        v_item.sort_order, COALESCE(v_item.modifiers, '{"removals":[],"additions":[]}'::jsonb)
      )
      RETURNING id INTO v_new_item_id;

      v_copied_items := v_copied_items + 1;

      INSERT INTO public.item_variants (item_id, size_key, size_label, price)
      SELECT v_new_item_id, size_key, size_label, price
      FROM public.item_variants
      WHERE item_id = v_item.id;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'success', TRUE,
    'source_slug', v_source_slug,
    'target_slug', v_target_slug,
    'copied_categories', v_copied_cats,
    'copied_items', v_copied_items
  );
END;
$$;

REVOKE ALL ON FUNCTION public.clone_restaurant_menu(TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clone_restaurant_menu(TEXT, TEXT, BOOLEAN) TO authenticated;
