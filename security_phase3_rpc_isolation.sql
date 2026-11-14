-- ==============================================================================
-- XUBO / GINGER PIZZA - GÜVENLİK FAZ 3 (ACİL RPC & TENANT İZOLASYONU)
-- ==============================================================================
-- Bu scripti Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Ne yapar:
--   1. master_platform_schema.sql / reports_and_customers_schema.sql'den kalan
--      tehlikeli açık RLS politikalarını (restaurants_master_all, *_anon_delete) kaldırır.
--   2. restaurants.admin_email sütununu anon okumasından kaldırır.
--   3. Tüm SECURITY DEFINER RPC fonksiyonlarına is_super_admin() / auth_restaurant_slug()
--      yetki kontrollerini ekler ve anon erişimini tamamen kapatır.
--   4. get_platform_restaurants_summary() içinden düz metin admin_password dönüşünü kaldırır.
--   5. copy_additions_to_all_pizzas() fonksiyonunu restaurant_id bazlı izole eder.
-- ==============================================================================

-- 1. Artık açık RLS politikalarını temizle
DROP POLICY IF EXISTS "restaurants_master_all" ON public.restaurants;
DROP POLICY IF EXISTS "orders_anon_delete" ON public.orders;
DROP POLICY IF EXISTS "order_items_anon_delete" ON public.order_items;
DROP POLICY IF EXISTS "customers_anon_delete" ON public.customers;

-- 2. restaurants.admin_email'i anon okumasından kaldır
REVOKE SELECT ON public.restaurants FROM anon;
GRANT SELECT (
  id, name, slug, custom_domain, phone, address, instagram,
  primary_color, is_active, created_at, updated_at
) ON public.restaurants TO anon;

-- 3. Master Panel RPC'lerini SADECE super_admin ile sınırla

-- 3a. create_restaurant_with_defaults
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
  -- Tahmin edilebilir '<slug>123' yerine rastgele güçlü geçici şifre
  v_random_pw := ENCODE(gen_random_bytes(9), 'base64');

  INSERT INTO public.restaurants (
    name, slug, custom_domain, phone, address, instagram,
    primary_color, admin_email, admin_password, is_active
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
    TRUE
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

-- 3b. set_restaurant_status
CREATE OR REPLACE FUNCTION public.set_restaurant_status(
  p_slug TEXT,
  p_is_active BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated INT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Sadece super_admin restoran durumunu değiştirebilir.';
  END IF;

  UPDATE public.restaurants
  SET is_active = p_is_active,
      updated_at = NOW()
  WHERE slug = TRIM(p_slug);
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Restoran bulunamadı: %', p_slug;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'slug', p_slug,
    'is_active', p_is_active
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_restaurant_status(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_restaurant_status(TEXT, BOOLEAN) TO authenticated;

-- 3c. delete_restaurant_permanently
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

-- 3d. get_platform_restaurants_summary (düz metin şifre dönmez, sadece super_admin)
CREATE OR REPLACE FUNCTION public.get_platform_restaurants_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Sadece super_admin platform özetini görebilir.';
  END IF;

  SELECT COALESCE(jsonb_agg(row_data), '[]'::jsonb) INTO v_result
  FROM (
    SELECT
      r.id,
      r.name,
      r.slug,
      r.custom_domain,
      r.phone,
      r.address,
      r.primary_color,
      COALESCE(
        NULLIF(TRIM(r.admin_email), ''),
        CASE WHEN r.slug = 'ginger-pizza' THEN 'admin@gingerpizza.com'
             ELSE 'admin@' || REGEXP_REPLACE(LOWER(r.slug), '[^a-z0-9]', '', 'g') || '.com' END
      ) AS admin_email,
      r.is_active,
      r.created_at,
      (SELECT COUNT(*)::INT FROM public.menu_items mi WHERE mi.restaurant_id = r.id) AS menu_items_count,
      (SELECT COUNT(*)::INT FROM public.orders o WHERE o.restaurant_slug = r.slug) AS total_orders_count,
      (SELECT COALESCE(SUM(o.total_amount), 0)::NUMERIC(10,2) FROM public.orders o WHERE o.restaurant_slug = r.slug AND o.status <> 'cancelled') AS total_revenue,
      (SELECT MAX(o.created_at) FROM public.orders o WHERE o.restaurant_slug = r.slug) AS last_order_at
    FROM public.restaurants r
    ORDER BY (r.slug = 'ginger-pizza') DESC, r.created_at ASC
  ) row_data;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_platform_restaurants_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_platform_restaurants_summary() TO authenticated;

-- 3e. update_restaurant_details
CREATE OR REPLACE FUNCTION public.update_restaurant_details(
  p_slug TEXT,
  p_name TEXT,
  p_phone TEXT DEFAULT '',
  p_address TEXT DEFAULT '',
  p_primary_color TEXT DEFAULT '#d86a1a',
  p_custom_domain TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := TRIM(COALESCE(p_slug, ''));
  v_clean_name TEXT := TRIM(COALESCE(p_name, ''));
  v_clean_domain TEXT := LOWER(REGEXP_REPLACE(TRIM(COALESCE(p_custom_domain, '')), '^https?://', '', 'i'));
  v_updated INT := 0;
BEGIN
  IF NOT (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND public.auth_restaurant_slug() = v_slug)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Bu restoranın bilgilerini güncelleme yetkiniz yok.';
  END IF;

  IF v_slug = '' THEN
    RAISE EXCEPTION 'Restoran slug boş olamaz.';
  END IF;
  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Restoran adı boş olamaz.';
  END IF;

  v_clean_domain := SPLIT_PART(v_clean_domain, '/', 1);

  UPDATE public.restaurants
  SET name = v_clean_name,
      phone = TRIM(COALESCE(p_phone, '')),
      address = TRIM(COALESCE(p_address, '')),
      primary_color = COALESCE(NULLIF(TRIM(p_primary_color), ''), '#d86a1a'),
      custom_domain = CASE
        WHEN public.is_super_admin() THEN NULLIF(v_clean_domain, '')
        ELSE custom_domain
      END,
      updated_at = NOW()
  WHERE slug = v_slug;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'Restoran bulunamadı: %', v_slug;
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'slug', v_slug,
    'name', v_clean_name,
    'custom_domain', NULLIF(v_clean_domain, '')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_restaurant_details(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_restaurant_details(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 4. Restoran bazlı geçmiş sıfırlama: Sadece ilgili restoran admini veya super_admin
CREATE OR REPLACE FUNCTION public.reset_restaurant_history(
  p_restaurant_slug TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := NULLIF(TRIM(COALESCE(p_restaurant_slug, '')), '');
  v_deleted_order_items INTEGER := 0;
  v_deleted_orders INTEGER := 0;
  v_deleted_customers INTEGER := 0;
BEGIN
  IF v_slug IS NULL THEN
    v_slug := NULLIF(public.auth_restaurant_slug(), '');
  END IF;

  IF v_slug IS NULL THEN
    RAISE EXCEPTION 'INVALID_SLUG: Restoran slug belirtilmelidir.';
  END IF;

  IF NOT (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND public.auth_restaurant_slug() = v_slug)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Başka bir restoranın geçmişini sıfırlayamazsınız.';
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

-- 5. İlave & ek ürün kopyalama: Sadece kendi restoranının ürünlerini günceller
DROP FUNCTION IF EXISTS public.copy_additions_to_all_pizzas(JSONB);

CREATE OR REPLACE FUNCTION public.copy_additions_to_all_pizzas(
  p_additions JSONB,
  p_restaurant_slug TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_rest_id UUID;
  v_updated_count INT := 0;
BEGIN
  IF NOT (public.is_super_admin() OR public.auth_role() = 'restaurant_admin') THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Bu işlem için yönetici yetkisi gerekir.';
  END IF;

  IF public.is_super_admin() AND NULLIF(TRIM(COALESCE(p_restaurant_slug, '')), '') IS NOT NULL THEN
    SELECT id INTO v_target_rest_id
    FROM public.restaurants
    WHERE slug = TRIM(p_restaurant_slug)
    LIMIT 1;
  ELSE
    v_target_rest_id := public.auth_restaurant_id();
  END IF;

  IF v_target_rest_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_TENANT: Hedef restoran belirlenemedi.';
  END IF;

  UPDATE public.menu_items
  SET
    modifiers = jsonb_set(
      COALESCE(modifiers, '{"removals": [], "additions": []}'::jsonb),
      '{additions}',
      COALESCE(p_additions, '[]'::jsonb),
      TRUE
    ),
    updated_at = NOW()
  WHERE is_pizza = TRUE
    AND restaurant_id = v_target_rest_id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$$;

REVOKE ALL ON FUNCTION public.copy_additions_to_all_pizzas(JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.copy_additions_to_all_pizzas(JSONB, TEXT) TO authenticated;
