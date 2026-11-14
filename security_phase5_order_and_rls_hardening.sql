-- ==============================================================================
-- XUBO / GINGER PIZZA - GÜVENLİK FAZ 5: SİPARİŞ SLUG ZORUNLULUĞU & ANON YAZMA KİLİDİ
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- 1. enforce_store_open_on_order(), sync_customer_on_order() ve
--    create_validated_order() içindeki 'ginger-pizza' varsayılan fallback'ini kaldırır;
--    slug boş gelirse açıkça RESTAURANT_SLUG_REQUIRED hatası fırlatır.
-- 2. anon rolünden tüm tablolardaki doğrudan INSERT/UPDATE/DELETE yetkilerini alır
--    (sipariş oluşturma yalnızca create_validated_order SECURITY DEFINER RPC ile yapılır).
-- ==============================================================================

-- 1. MAĞAZA AÇIK/KAPALI TRIGGER'I — BOŞ SLUG'I REDDET
CREATE OR REPLACE FUNCTION public.enforce_store_open_on_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s RECORD;
  tr_now TIMESTAMP;
  tr_dow INT;
  prev_dow INT;
  cur_time TEXT;
  day_cfg JSONB;
  prev_cfg JSONB;
  open_str TEXT;
  close_str TEXT;
  prev_open TEXT;
  prev_close TEXT;
  is_open BOOLEAN := FALSE;
  target_slug TEXT;
BEGIN
  target_slug := NULLIF(LOWER(TRIM(NEW.restaurant_slug)), '');
  IF target_slug IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_SLUG_REQUIRED: Sipariş için restoran bilgisi (restaurant_slug) zorunludur.';
  END IF;
  NEW.restaurant_slug := target_slug;

  SELECT * INTO s
  FROM public.store_settings
  WHERE id = target_slug
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF s.order_mode = 'manual_closed' THEN
    RAISE EXCEPTION 'STORE_CLOSED: %', COALESCE(NULLIF(s.status_message, ''), 'Dükkanımız şu anda siparişe geçici olarak kapalıdır.');
  END IF;

  IF s.order_mode = 'manual_open' THEN
    RETURN NEW;
  END IF;

  IF s.order_mode = 'busy' THEN
    IF s.busy_until IS NULL OR s.busy_until > NOW() THEN
      RAISE EXCEPTION 'STORE_BUSY: %', COALESCE(NULLIF(s.status_message, ''), 'Yoğunluk nedeniyle şu anda geçici olarak sipariş alamıyoruz.');
    END IF;
  END IF;

  tr_now := NOW() AT TIME ZONE 'Europe/Istanbul';
  tr_dow := EXTRACT(DOW FROM tr_now)::INT;
  prev_dow := (tr_dow + 6) % 7;
  cur_time := TO_CHAR(tr_now, 'HH24:MI');

  day_cfg := s.weekly_hours -> (tr_dow::TEXT);
  IF day_cfg IS NOT NULL AND COALESCE((day_cfg->>'enabled')::BOOLEAN, TRUE) THEN
    open_str := COALESCE(day_cfg->>'open', '11:30');
    close_str := COALESCE(day_cfg->>'close', '23:00');
    IF close_str >= open_str THEN
      IF cur_time >= open_str AND cur_time < close_str THEN
        is_open := TRUE;
      END IF;
    ELSE
      IF cur_time >= open_str THEN
        is_open := TRUE;
      END IF;
    END IF;
  END IF;

  IF NOT is_open THEN
    prev_cfg := s.weekly_hours -> (prev_dow::TEXT);
    IF prev_cfg IS NOT NULL AND COALESCE((prev_cfg->>'enabled')::BOOLEAN, TRUE) THEN
      prev_open := COALESCE(prev_cfg->>'open', '11:30');
      prev_close := COALESCE(prev_cfg->>'close', '23:00');
      IF prev_close < prev_open AND cur_time < prev_close THEN
        is_open := TRUE;
      END IF;
    END IF;
  END IF;

  IF NOT is_open THEN
    RAISE EXCEPTION 'STORE_OUTSIDE_HOURS: %', COALESCE(NULLIF(s.status_message, ''), 'Çalışma saatlerimiz dışındayız. Lütfen çalışma saatlerimizde tekrar deneyin.');
  END IF;

  RETURN NEW;
END;
$$;

-- 2. MÜŞTERİ SENKRONİZASYON TRIGGER'I — BOŞ SLUG'I REDDET
CREATE OR REPLACE FUNCTION public.sync_customer_on_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  norm_phone TEXT;
  slug TEXT;
  clean_addr TEXT;
BEGIN
  norm_phone := public.normalize_tr_phone(NEW.customer_phone);
  IF norm_phone = '' THEN
    RETURN NEW;
  END IF;

  slug := NULLIF(LOWER(TRIM(NEW.restaurant_slug)), '');
  IF slug IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_SLUG_REQUIRED: Müşteri kaydı için restoran bilgisi zorunludur.';
  END IF;
  clean_addr := COALESCE(NEW.delivery_address, '');

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.status, 'new') <> 'cancelled' THEN
      INSERT INTO public.customers (
        restaurant_slug,
        phone_normalized,
        phone_display,
        customer_name,
        last_address,
        order_count,
        total_spent,
        last_order_at,
        updated_at
      )
      VALUES (
        slug,
        norm_phone,
        COALESCE(NULLIF(TRIM(NEW.customer_phone), ''), norm_phone),
        COALESCE(NULLIF(TRIM(NEW.customer_name), ''), 'Müşteri'),
        clean_addr,
        1,
        COALESCE(NEW.total_amount, 0),
        COALESCE(NEW.created_at, NOW()),
        NOW()
      )
      ON CONFLICT (restaurant_slug, phone_normalized) DO UPDATE
      SET
        phone_display = EXCLUDED.phone_display,
        customer_name = EXCLUDED.customer_name,
        last_address = CASE
          WHEN NULLIF(TRIM(EXCLUDED.last_address), '') IS NOT NULL
               AND EXCLUDED.last_address <> 'Gel-Al Siparişi'
          THEN EXCLUDED.last_address
          ELSE public.customers.last_address
        END,
        order_count = public.customers.order_count + 1,
        total_spent = public.customers.total_spent + EXCLUDED.total_spent,
        last_order_at = GREATEST(COALESCE(public.customers.last_order_at, EXCLUDED.last_order_at), EXCLUDED.last_order_at),
        updated_at = NOW();
    END IF;
  ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    IF COALESCE(OLD.status, '') <> 'cancelled' AND NEW.status = 'cancelled' THEN
      UPDATE public.customers
      SET
        order_count = GREATEST(0, order_count - 1),
        total_spent = GREATEST(0, total_spent - COALESCE(NEW.total_amount, 0)),
        updated_at = NOW()
      WHERE restaurant_slug = slug AND phone_normalized = norm_phone;
    ELSIF OLD.status = 'cancelled' AND COALESCE(NEW.status, '') <> 'cancelled' THEN
      UPDATE public.customers
      SET
        order_count = order_count + 1,
        total_spent = total_spent + COALESCE(NEW.total_amount, 0),
        updated_at = NOW()
      WHERE restaurant_slug = slug AND phone_normalized = norm_phone;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. DOĞRULANMIŞ SİPARİŞ RPC'Sİ — BOŞ SLUG'I REDDET ('ginger-pizza' FALLBACK YOK)
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

  -- Her sepet kaleminin fiyatını veritabanından doğrula
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

-- 4. ANON DOĞRUDAN YAZMA YETKİLERİNİ TABLO DÜZEYİNDE KAPAT
REVOKE INSERT, UPDATE, DELETE ON public.restaurants FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.categories FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.menu_items FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.item_variants FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.store_settings FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.customers FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.orders FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.order_items FROM anon;
