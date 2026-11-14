-- ==============================================================================
-- XUBO / GINGER PIZZA - FAZ 8: ŞABLON / MAĞAZADAN MAĞAZAYA MENÜ KOPYALAMA,
-- MİNİMUM PAKET TUTARI & TESLİMAT ÜCRETİ DOĞRULAMASI
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Ne yapar:
--   1. store_settings tablosuna min_order_amount (Minimum Paket Tutarı) ve
--      delivery_fee (Paket Servis Teslimat Ücreti) sütunlarını ekler.
--   2. orders tablosuna delivery_fee sütununu ekler.
--   3. create_validated_order() fonksiyonuna Minimum Paket Tutarı kontrolü ve
--      Teslimat Ücreti hesaplamasını ekler.
--   4. clone_restaurant_menu(p_source_slug, p_target_slug, p_replace_existing)
--      fonksiyonu ile hazır sektör şablonu (Pizza / Burger) veya mevcut bir
--      mağazanın tüm menüsünü (kategoriler + ürünler + varyantlar + ilaveler)
--      hedef mağazaya tek tıkla kopyalar.
-- ==============================================================================

-- 1. store_settings ve orders tablolarına yeni sütunlar
ALTER TABLE public.store_settings
  ADD COLUMN IF NOT EXISTS min_order_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(10, 2) NOT NULL DEFAULT 0;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(10, 2) NOT NULL DEFAULT 0;


-- 2. create_validated_order() — Minimum Paket Tutarı & Teslimat Ücreti Destekli
CREATE OR REPLACE FUNCTION public.create_validated_order(
  p_restaurant_slug TEXT,
  p_customer JSONB,
  p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT;
  v_restaurant RECORD;
  v_settings RECORD;
  v_item JSONB;
  v_menu_item RECORD;
  v_variant RECORD;
  v_req_add JSONB;
  v_db_add JSONB;
  v_qty INTEGER;
  v_size_key TEXT;
  v_size_label TEXT;
  v_base_price NUMERIC(10, 2);
  v_add_price NUMERIC(10, 2);
  v_additions_total NUMERIC(10, 2);
  v_unit_price NUMERIC(10, 2);
  v_line_total NUMERIC(10, 2);
  v_subtotal NUMERIC(10, 2) := 0;
  v_discount_enabled BOOLEAN := FALSE;
  v_discount_percent NUMERIC(5, 2) := 0;
  v_discount_amount NUMERIC(10, 2) := 0;
  v_after_discount NUMERIC(10, 2) := 0;
  v_min_order_amount NUMERIC(10, 2) := 0;
  v_delivery_fee NUMERIC(10, 2) := 0;
  v_final_total NUMERIC(10, 2) := 0;
  v_delivery_type TEXT;
  v_payment_method TEXT;
  v_customer_name TEXT;
  v_customer_phone TEXT;
  v_norm_phone TEXT;
  v_recent_phone_orders INT := 0;
  v_recent_store_orders INT := 0;
  v_delivery_address TEXT;
  v_order_notes TEXT;
  v_tracking_token UUID := gen_random_uuid();
  v_order RECORD;
  v_validated_items JSONB := '[]'::JSONB;
  v_req_add_name TEXT;
  v_matched_add BOOLEAN;
BEGIN
  v_slug := NULLIF(LOWER(TRIM(p_restaurant_slug)), '');
  IF v_slug IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_SLUG_REQUIRED: Sipariş için restoran bilgisi zorunludur.';
  END IF;

  SELECT id, slug, name, is_active
  INTO v_restaurant
  FROM public.restaurants
  WHERE slug = v_slug
  LIMIT 1;

  IF v_restaurant.id IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_NOT_FOUND: Restoran bulunamadı (%).', v_slug;
  END IF;

  IF NOT COALESCE(v_restaurant.is_active, TRUE) THEN
    RAISE EXCEPTION 'STORE_CLOSED: Restoran şu anda aktif değil.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART: Sepet boş olamaz.';
  END IF;

  v_customer_name := NULLIF(TRIM(COALESCE(p_customer ->> 'name', '')), '');
  v_customer_phone := NULLIF(TRIM(COALESCE(p_customer ->> 'phone', '')), '');
  IF v_customer_name IS NULL OR v_customer_phone IS NULL THEN
    RAISE EXCEPTION 'INVALID_CUSTOMER: Müşteri adı ve telefonu zorunludur.';
  END IF;

  -- Sipariş spam / rate-limit kontrolü
  v_norm_phone := regexp_replace(v_customer_phone, '[^0-9]', '', 'g');
  IF length(v_norm_phone) >= 10 THEN
    v_norm_phone := right(v_norm_phone, 10);
    SELECT COUNT(*)::INT INTO v_recent_phone_orders
    FROM public.orders
    WHERE restaurant_slug = v_slug
      AND created_at > NOW() - INTERVAL '2 minutes'
      AND right(regexp_replace(COALESCE(customer_phone, ''), '[^0-9]', '', 'g'), 10) = v_norm_phone;

    IF v_recent_phone_orders >= 2 THEN
      RAISE EXCEPTION 'RATE_LIMIT_EXCEEDED: Kısa sürede çok fazla sipariş gönderdiniz. Lütfen 1-2 dakika bekleyip tekrar deneyin.';
    END IF;
  END IF;

  SELECT COUNT(*)::INT INTO v_recent_store_orders
  FROM public.orders
  WHERE restaurant_slug = v_slug
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_store_orders >= 30 THEN
    RAISE EXCEPTION 'RATE_LIMIT_EXCEEDED: Yoğunluk nedeniyle geçici sipariş koruması devrede. Lütfen biraz sonra tekrar deneyin.';
  END IF;

  v_delivery_type := CASE
    WHEN COALESCE(p_customer ->> 'deliveryType', 'delivery') = 'takeaway' THEN 'takeaway'
    ELSE 'delivery'
  END;
  v_payment_method := COALESCE(NULLIF(TRIM(p_customer ->> 'paymentMethod'), ''), 'door_card');
  v_delivery_address := CASE
    WHEN v_delivery_type = 'takeaway' THEN COALESCE(NULLIF(TRIM(p_customer ->> 'address'), ''), 'Gel-Al Siparişi')
    ELSE COALESCE(NULLIF(TRIM(p_customer ->> 'address'), ''), '')
  END;
  v_order_notes := COALESCE(TRIM(p_customer ->> 'notes'), '');

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := GREATEST(1, LEAST(99, COALESCE((v_item ->> 'quantity')::INTEGER, 1)));

    SELECT id, restaurant_id, name, is_available, is_pizza, fixed_price, modifiers
    INTO v_menu_item
    FROM public.menu_items
    WHERE restaurant_id = v_restaurant.id
      AND id::TEXT = TRIM(COALESCE(v_item ->> 'id', ''))
    LIMIT 1;

    IF v_menu_item.id IS NULL THEN
      RAISE EXCEPTION 'INVALID_MENU_ITEM: Ürün bulunamadı veya bu restorana ait değil.';
    END IF;

    IF NOT COALESCE(v_menu_item.is_available, TRUE) THEN
      RAISE EXCEPTION 'ITEM_UNAVAILABLE: "%" şu anda stokta değil.', v_menu_item.name;
    END IF;

    IF COALESCE(v_menu_item.is_pizza, FALSE) THEN
      v_size_key := COALESCE(NULLIF(LOWER(TRIM(v_item ->> 'sizeKey')), ''), 'medium');
      SELECT size_label, price
      INTO v_variant
      FROM public.item_variants
      WHERE item_id = v_menu_item.id
        AND LOWER(size_key) = v_size_key
      LIMIT 1;

      IF v_variant.price IS NULL THEN
        SELECT size_label, price
        INTO v_variant
        FROM public.item_variants
        WHERE item_id = v_menu_item.id
        ORDER BY CASE LOWER(size_key) WHEN 'medium' THEN 1 WHEN 'small' THEN 2 ELSE 3 END
        LIMIT 1;
      END IF;

      IF v_variant.price IS NULL THEN
        v_base_price := COALESCE(v_menu_item.fixed_price, 0);
        v_size_label := COALESCE(NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), 'Orta');
      ELSE
        v_base_price := GREATEST(0, COALESCE(v_variant.price, 0));
        v_size_label := COALESCE(NULLIF(TRIM(v_variant.size_label), ''), NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), v_size_key);
      END IF;
    ELSE
      v_size_key := NULL;
      v_base_price := GREATEST(0, COALESCE(v_menu_item.fixed_price, 0));
      v_size_label := COALESCE(NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), 'Tek Porsiyon');
    END IF;

    v_additions_total := 0;
    IF v_item -> 'additions' IS NOT NULL AND jsonb_typeof(v_item -> 'additions') = 'array' THEN
      FOR v_req_add IN SELECT * FROM jsonb_array_elements(v_item -> 'additions')
      LOOP
        v_req_add_name := LOWER(TRIM(COALESCE(v_req_add ->> 'name', '')));
        IF v_req_add_name <> '' AND jsonb_typeof(v_menu_item.modifiers -> 'additions') = 'array' THEN
          v_matched_add := FALSE;
          v_add_price := 0;
          FOR v_db_add IN SELECT * FROM jsonb_array_elements(v_menu_item.modifiers -> 'additions')
          LOOP
            IF LOWER(TRIM(COALESCE(v_db_add ->> 'name', ''))) = v_req_add_name THEN
              v_matched_add := TRUE;
              IF COALESCE(v_menu_item.is_pizza, FALSE) AND jsonb_typeof(v_db_add -> 'prices') = 'object' THEN
                v_add_price := GREATEST(
                  0,
                  COALESCE(
                    NULLIF(v_db_add -> 'prices' ->> COALESCE(v_size_key, 'medium'), '')::NUMERIC,
                    NULLIF(v_db_add -> 'prices' ->> 'medium', '')::NUMERIC,
                    NULLIF(v_db_add -> 'prices' ->> 'small', '')::NUMERIC,
                    NULLIF(v_db_add ->> 'price', '')::NUMERIC,
                    0
                  )
                );
              ELSE
                v_add_price := GREATEST(
                  0,
                  COALESCE(
                    NULLIF(v_db_add ->> 'price', '')::NUMERIC,
                    NULLIF(v_db_add -> 'prices' ->> 'medium', '')::NUMERIC,
                    0
                  )
                );
              END IF;
              EXIT;
            END IF;
          END LOOP;
          IF v_matched_add THEN
            v_additions_total := v_additions_total + v_add_price;
          END IF;
        END IF;
      END LOOP;
    END IF;

    v_unit_price := ROUND(v_base_price + v_additions_total, 2);
    v_line_total := ROUND(v_unit_price * v_qty, 2);
    v_subtotal := v_subtotal + v_line_total;

    v_validated_items := v_validated_items || jsonb_build_array(
      jsonb_build_object(
        'item_name', v_menu_item.name,
        'size_label', v_size_label,
        'quantity', v_qty,
        'unit_price', v_unit_price,
        'total_price', v_line_total,
        'item_notes', COALESCE(TRIM(v_item ->> 'notes'), '')
      )
    );
  END LOOP;

  SELECT
    online_discount_enabled,
    online_discount_percent,
    COALESCE(min_order_amount, 0) AS min_order_amount,
    COALESCE(delivery_fee, 0) AS delivery_fee
  INTO v_settings
  FROM public.store_settings
  WHERE id = v_slug
  LIMIT 1;

  v_discount_enabled := COALESCE(v_settings.online_discount_enabled, FALSE);
  v_discount_percent := CASE
    WHEN v_discount_enabled THEN GREATEST(0, LEAST(100, COALESCE(v_settings.online_discount_percent, 0)))
    ELSE 0
  END;
  v_discount_amount := ROUND(v_subtotal * (v_discount_percent / 100.0), 2);
  v_after_discount := GREATEST(0, ROUND(v_subtotal - v_discount_amount, 2));

  v_min_order_amount := GREATEST(0, COALESCE(v_settings.min_order_amount, 0));
  IF v_delivery_type = 'delivery' AND v_min_order_amount > 0 AND v_after_discount < v_min_order_amount THEN
    RAISE EXCEPTION 'MIN_ORDER_NOT_MET: Paket servis için minimum sipariş tutarı % ₺ olmalıdır.', ROUND(v_min_order_amount, 0);
  END IF;

  v_delivery_fee := CASE
    WHEN v_delivery_type = 'delivery' THEN GREATEST(0, COALESCE(v_settings.delivery_fee, 0))
    ELSE 0
  END;

  v_final_total := GREATEST(0, ROUND(v_after_discount + v_delivery_fee, 2));

  INSERT INTO public.orders (
    restaurant_slug,
    customer_name,
    customer_phone,
    delivery_type,
    delivery_address,
    order_notes,
    payment_method,
    subtotal_amount,
    discount_percent,
    discount_amount,
    delivery_fee,
    total_amount,
    status,
    tracking_token
  )
  VALUES (
    v_slug,
    v_customer_name,
    v_customer_phone,
    v_delivery_type,
    v_delivery_address,
    v_order_notes,
    v_payment_method,
    v_subtotal,
    v_discount_percent,
    v_discount_amount,
    v_delivery_fee,
    v_final_total,
    'new',
    v_tracking_token
  )
  RETURNING * INTO v_order;

  INSERT INTO public.order_items (
    order_id,
    item_name,
    size_label,
    quantity,
    unit_price,
    total_price,
    item_notes
  )
  SELECT
    v_order.id,
    x ->> 'item_name',
    COALESCE(x ->> 'size_label', ''),
    (x ->> 'quantity')::INTEGER,
    (x ->> 'unit_price')::NUMERIC,
    (x ->> 'total_price')::NUMERIC,
    COALESCE(x ->> 'item_notes', '')
  FROM jsonb_array_elements(v_validated_items) AS x;

  RETURN jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'restaurant_slug', v_order.restaurant_slug,
    'tracking_token', v_order.tracking_token,
    'customer_name', v_order.customer_name,
    'delivery_type', v_order.delivery_type,
    'payment_method', v_order.payment_method,
    'subtotal_amount', v_order.subtotal_amount,
    'discount_percent', v_order.discount_percent,
    'discount_amount', v_order.discount_amount,
    'delivery_fee', v_order.delivery_fee,
    'total_amount', v_order.total_amount,
    'status', v_order.status,
    'created_at', v_order.created_at,
    'items', v_validated_items
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_validated_order(TEXT, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_validated_order(TEXT, JSONB, JSONB) TO anon, authenticated;


-- 3. Şablon veya Mevcut Mağazadan Menü Kopyalama RPC'si
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
  IF v_target_slug = '' OR v_source_slug = '' THEN
    RAISE EXCEPTION 'INVALID_SLUG: Kaynak ve hedef mağaza bilgisi zorunludur.';
  END IF;

  IF v_target_slug = v_source_slug THEN
    RAISE EXCEPTION 'INVALID_TARGET: Kaynak ve hedef mağaza aynı olamaz.';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND public.auth_restaurant_slug() = v_target_slug)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Bu mağazaya menü kopyalama yetkiniz yok.';
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
