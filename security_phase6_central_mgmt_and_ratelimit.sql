-- ==============================================================================
-- XUBO / GINGER PIZZA - PAKET 2: VERİTABANI GÜVENLİK & MERKEZİ YÖNETİM SERTLEŞTİRME
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- 1. auth_restaurant_id() fonksiyonuna slug üzerinden UUID fallback ekler.
-- 2. create_validated_order() içine sipariş spam / rate-limit koruması ekler.
-- 3. create_restaurant_with_defaults() yeni mağaza açılışında varsayılan kategorileri ekler.
-- 4. delete_restaurant_permanently() mağaza silerken item_variants, menu_items ve
--    categories kayıtlarını da eksiksiz temizler.
-- 5. restaurants.admin_password sütunundaki eski düz metin kalıntılarını NULL yapar.
-- ==============================================================================

-- 1. auth_restaurant_id() — JWT'de restaurant_id yoksa restaurant_slug'dan UUID bul
CREATE OR REPLACE FUNCTION public.auth_restaurant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw TEXT;
  v_slug TEXT;
  v_id UUID;
BEGIN
  v_raw := NULLIF(TRIM(COALESCE(auth.jwt() -> 'app_metadata' ->> 'restaurant_id', '')), '');
  IF v_raw IS NOT NULL THEN
    BEGIN
      RETURN v_raw::UUID;
    EXCEPTION WHEN invalid_text_representation THEN
      NULL;
    END;
  END IF;

  v_slug := NULLIF(LOWER(TRIM(COALESCE(auth.jwt() -> 'app_metadata' ->> 'restaurant_slug', ''))), '');
  IF v_slug IS NOT NULL THEN
    SELECT id INTO v_id
    FROM public.restaurants
    WHERE slug = v_slug
    LIMIT 1;
    RETURN v_id;
  END IF;

  RETURN NULL;
END;
$$;

-- 2. create_validated_order() — Spam / Rate-Limit korumalı sürüm
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

  SELECT online_discount_enabled, online_discount_percent
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
  v_final_total := GREATEST(0, ROUND(v_subtotal - v_discount_amount, 2));

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
    'total_amount', v_order.total_amount,
    'status', v_order.status,
    'created_at', v_order.created_at,
    'items', v_validated_items
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_validated_order(TEXT, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_validated_order(TEXT, JSONB, JSONB) TO anon, authenticated;

-- 3. create_restaurant_with_defaults() — Varsayılan başlangıç kategorileriyle birlikte aç
CREATE OR REPLACE FUNCTION public.create_restaurant_with_defaults(
  p_name TEXT,
  p_slug TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT '',
  p_address TEXT DEFAULT '',
  p_instagram TEXT DEFAULT '',
  p_primary_color TEXT DEFAULT '#d86a1a',
  p_custom_domain TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_name TEXT := TRIM(COALESCE(p_name, ''));
  v_slug TEXT;
  v_restaurant_id UUID;
  v_count INT := 0;
  v_base_slug TEXT;
  v_cred_slug TEXT;
  v_admin_email TEXT;
  v_random_pw TEXT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Sadece super_admin yeni restoran oluşturabilir.';
  END IF;

  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Restoran adı boş olamaz.';
  END IF;

  IF p_slug IS NOT NULL AND TRIM(p_slug) <> '' THEN
    v_slug := public.slugify_restaurant_name(p_slug);
  ELSE
    v_slug := public.slugify_restaurant_name(v_clean_name);
  END IF;

  v_base_slug := v_slug;
  WHILE EXISTS (SELECT 1 FROM public.restaurants WHERE slug = v_slug) LOOP
    v_count := v_count + 1;
    v_slug := v_base_slug || '-' || v_count;
  END LOOP;

  v_cred_slug := REGEXP_REPLACE(LOWER(v_slug), '[^a-z0-9]', '', 'g');
  IF v_cred_slug = '' THEN
    v_cred_slug := 'restoran';
  END IF;
  v_admin_email := 'admin@' || v_cred_slug || '.com';
  v_random_pw := ENCODE(gen_random_bytes(9), 'base64');

  INSERT INTO public.restaurants (
    name, slug, custom_domain, phone, address, instagram,
    primary_color, admin_email, admin_password, is_active, profile
  ) VALUES (
    v_clean_name,
    v_slug,
    NULLIF(TRIM(COALESCE(p_custom_domain, '')), ''),
    TRIM(COALESCE(p_phone, '')),
    TRIM(COALESCE(p_address, '')),
    TRIM(COALESCE(p_instagram, '')),
    COALESCE(NULLIF(TRIM(p_primary_color), ''), '#d86a1a'),
    v_admin_email,
    NULL,
    TRUE,
    '{}'::jsonb
  )
  RETURNING id INTO v_restaurant_id;

  INSERT INTO public.store_settings (
    id, order_mode, status_message, weekly_hours,
    online_discount_enabled, online_discount_percent, payment_methods, updated_at
  ) VALUES (
    v_slug,
    'auto',
    '',
    '{
      "1": {"enabled": true, "open": "11:30", "close": "23:00"},
      "2": {"enabled": true, "open": "11:30", "close": "23:00"},
      "3": {"enabled": true, "open": "11:30", "close": "23:00"},
      "4": {"enabled": true, "open": "11:30", "close": "23:00"},
      "5": {"enabled": true, "open": "11:30", "close": "23:00"},
      "6": {"enabled": true, "open": "11:30", "close": "23:00"},
      "0": {"enabled": true, "open": "11:30", "close": "23:00"}
    }'::jsonb,
    FALSE,
    0,
    '[
      {"id": "door_card", "label": "Kapıda Kredi Kartı", "icon": "💳", "enabled": true, "isDefault": true},
      {"id": "door_cash", "label": "Kapıda Nakit", "icon": "💵", "enabled": true, "isDefault": true}
    ]'::jsonb,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;

  -- Yeni mağaza admin panelinde hemen ürün ekleyebilsin diye başlangıç kategorileri
  INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
  VALUES
    (v_restaurant_id, 'ana-urunler', 'Ana Ürünler', 1),
    (v_restaurant_id, 'menuler', 'Menüler', 2),
    (v_restaurant_id, 'yan-urunler', 'Yan Ürünler & Soslar', 3),
    (v_restaurant_id, 'icecekler', 'İçecekler & Tatlılar', 4)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'success', TRUE,
    'id', v_restaurant_id,
    'name', v_clean_name,
    'slug', v_slug,
    'admin_email', v_admin_email,
    'suggested_temp_password', v_random_pw,
    'is_active', TRUE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_restaurant_with_defaults(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_restaurant_with_defaults(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 4. delete_restaurant_permanently() — Menü, varyant ve kategorileri de eksiksiz temizle
CREATE OR REPLACE FUNCTION public.delete_restaurant_permanently(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := TRIM(COALESCE(p_slug, ''));
  v_rest_id UUID;
  v_deleted_orders INT := 0;
  v_deleted_customers INT := 0;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Sadece super_admin restoran silebilir.';
  END IF;

  IF v_slug = '' OR v_slug = 'ginger-pizza' THEN
    RAISE EXCEPTION 'Ana referans restoran (ginger-pizza) silinemez!';
  END IF;

  SELECT id INTO v_rest_id FROM public.restaurants WHERE slug = v_slug;
  IF v_rest_id IS NULL THEN
    RAISE EXCEPTION 'Silinecek restoran bulunamadı: %', v_slug;
  END IF;

  DELETE FROM public.order_items oi
  USING public.orders o
  WHERE oi.order_id = o.id
    AND o.restaurant_slug = v_slug;

  DELETE FROM public.orders
  WHERE restaurant_slug = v_slug;
  GET DIAGNOSTICS v_deleted_orders = ROW_COUNT;

  DELETE FROM public.customers
  WHERE restaurant_slug = v_slug;
  GET DIAGNOSTICS v_deleted_customers = ROW_COUNT;

  DELETE FROM public.item_variants iv
  USING public.menu_items mi
  WHERE iv.item_id = mi.id
    AND mi.restaurant_id = v_rest_id;

  DELETE FROM public.menu_items WHERE restaurant_id = v_rest_id;
  DELETE FROM public.categories WHERE restaurant_id = v_rest_id;
  DELETE FROM public.store_settings WHERE id = v_slug;
  DELETE FROM public.restaurants WHERE id = v_rest_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'deleted_slug', v_slug,
    'deleted_orders', v_deleted_orders,
    'deleted_customers', v_deleted_customers
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_restaurant_permanently(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_restaurant_permanently(TEXT) TO authenticated;

-- 5. Eski düz metin admin_password kalıntılarını temizle
UPDATE public.restaurants
SET admin_password = NULL
WHERE admin_password IS NOT NULL;
