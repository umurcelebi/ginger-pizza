-- ==============================================================================
-- XUBO / GINGER PIZZA - GÜVENLİK FAZ 2 (ADIM 1: ZERO-DOWNTIME HAZIRLIK)
-- ==============================================================================
-- Bu script mevcut çalışan restoranları KESİNTİYE UĞRATMADAN:
--   1. orders tablosuna tracking_token sütunu ekler
--   2. Supabase Auth JWT (app_metadata) yardımcı fonksiyonlarını oluşturur
--   3. Fiyat/indirim doğrulamalı create_validated_order() RPC fonksiyonunu ekler
--   4. Token korumalı get_order_tracking() RPC fonksiyonunu ekler
-- NOT: Mevcut RLS politikaları ADIM 2'de (Auth geçişi tamamlanınca) sıkılaştırılacaktır.
-- ==============================================================================

-- 1. Sipariş takip token'ı sütunu
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tracking_token UUID DEFAULT gen_random_uuid();

UPDATE public.orders
SET tracking_token = gen_random_uuid()
WHERE tracking_token IS NULL;

CREATE INDEX IF NOT EXISTS idx_orders_id_tracking_token
  ON public.orders (id, tracking_token);

-- 2. Auth JWT (app_metadata) yardımcı fonksiyonları
CREATE OR REPLACE FUNCTION public.auth_role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '');
$$;

CREATE OR REPLACE FUNCTION public.auth_restaurant_slug()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'restaurant_slug', '');
$$;

CREATE OR REPLACE FUNCTION public.auth_restaurant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_raw TEXT;
BEGIN
  v_raw := NULLIF(TRIM(COALESCE(auth.jwt() -> 'app_metadata' ->> 'restaurant_id', '')), '');
  IF v_raw IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN v_raw::UUID;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT public.auth_role() = 'super_admin';
$$;

-- 3. Sunucu taraflı fiyat & indirim doğrulamalı sipariş oluşturma RPC'si
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
  v_slug := COALESCE(NULLIF(LOWER(TRIM(p_restaurant_slug)), ''), 'ginger-pizza');

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
        -- Varyant bulunamazsa medium veya ilk varyantı dene
        SELECT size_label, price
        INTO v_variant
        FROM public.item_variants
        WHERE item_id = v_menu_item.id
        ORDER BY CASE LOWER(size_key) WHEN 'medium' THEN 1 WHEN 'small' THEN 2 ELSE 3 END
        LIMIT 1;
      END IF;

      IF v_variant.price IS NULL THEN
        v_base_price := COALESCE(v_menu_item.fixed_price, 0);
        v_size_label := COALESCE(NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), 'Medium (30-32 cm)');
      ELSE
        v_base_price := GREATEST(0, COALESCE(v_variant.price, 0));
        v_size_label := COALESCE(NULLIF(TRIM(v_variant.size_label), ''), NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), v_size_key);
      END IF;
    ELSE
      v_size_key := NULL;
      v_base_price := GREATEST(0, COALESCE(v_menu_item.fixed_price, 0));
      v_size_label := COALESCE(NULLIF(TRIM(v_item ->> 'sizeLabel'), ''), 'Tek Porsiyon');
    END IF;

    -- Ekstra malzeme / ilave ürün fiyatlarını sunucuda doğrula
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

  -- Online indirim ayarını sunucudan oku
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

-- 4. Token korumalı müşteri sipariş takip RPC'si
CREATE OR REPLACE FUNCTION public.get_order_tracking(
  p_order_id UUID,
  p_tracking_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_items JSONB;
BEGIN
  IF p_order_id IS NULL OR p_tracking_token IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT
    id,
    order_number,
    restaurant_slug,
    status,
    delivery_type,
    payment_method,
    subtotal_amount,
    discount_percent,
    discount_amount,
    total_amount,
    created_at,
    updated_at
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND tracking_token = p_tracking_token
  LIMIT 1;

  IF v_order.id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'item_name', item_name,
        'size_label', size_label,
        'quantity', quantity,
        'unit_price', unit_price,
        'total_price', total_price,
        'item_notes', item_notes
      )
    ),
    '[]'::JSONB
  )
  INTO v_items
  FROM public.order_items
  WHERE order_id = v_order.id;

  RETURN jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'restaurant_slug', v_order.restaurant_slug,
    'status', v_order.status,
    'delivery_type', v_order.delivery_type,
    'payment_method', v_order.payment_method,
    'subtotal_amount', v_order.subtotal_amount,
    'discount_percent', v_order.discount_percent,
    'discount_amount', v_order.discount_amount,
    'total_amount', v_order.total_amount,
    'created_at', v_order.created_at,
    'updated_at', v_order.updated_at,
    'items', v_items
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_order_tracking(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_order_tracking(UUID, UUID) TO anon, authenticated;
