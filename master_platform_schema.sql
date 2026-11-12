-- ============================================================================
-- MASTER PLATFORM & ÇOKLU RESTORAN OTOMASYONU ŞEMASI
-- Supabase SQL Editor üzerinden çalıştırın.
-- ============================================================================

-- 1. Slug Temizleme / Normalizasyon Fonksiyonu
CREATE OR REPLACE FUNCTION public.slugify_restaurant_name(p_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_slug TEXT;
BEGIN
  v_slug := LOWER(TRIM(p_name));
  -- Türkçe karakter dönüşümü
  v_slug := REPLACE(v_slug, 'ç', 'c');
  v_slug := REPLACE(v_slug, 'ğ', 'g');
  v_slug := REPLACE(v_slug, 'ı', 'i');
  v_slug := REPLACE(v_slug, 'ö', 'o');
  v_slug := REPLACE(v_slug, 'ş', 's');
  v_slug := REPLACE(v_slug, 'ü', 'u');
  -- Alfanümerik olmayanları tire ile değiştir
  v_slug := REGEXP_REPLACE(v_slug, '[^a-z0-9]+', '-', 'g');
  -- Baştaki ve sondaki tireleri temizle
  v_slug := TRIM(BOTH '-' FROM v_slug);
  IF v_slug = '' THEN
    v_slug := 'restoran-' || SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 6);
  END IF;
  RETURN v_slug;
END;
$$;

-- 2. Yeni Restoran Otomatik Kurulum RPC (Provisioning)
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
BEGIN
  IF v_clean_name = '' THEN
    RAISE EXCEPTION 'Restoran adı boş olamaz.';
  END IF;

  -- Slug belirle
  IF p_slug IS NOT NULL AND TRIM(p_slug) <> '' THEN
    v_slug := public.slugify_restaurant_name(p_slug);
  ELSE
    v_slug := public.slugify_restaurant_name(v_clean_name);
  END IF;

  -- Benzersiz slug sağla
  v_base_slug := v_slug;
  WHILE EXISTS (SELECT 1 FROM public.restaurants WHERE slug = v_slug) LOOP
    v_count := v_count + 1;
    v_slug := v_base_slug || '-' || v_count;
  END LOOP;

  -- 1. Restoran Kaydını Aç
  INSERT INTO public.restaurants (
    name,
    slug,
    custom_domain,
    phone,
    address,
    instagram,
    primary_color,
    is_active
  ) VALUES (
    v_clean_name,
    v_slug,
    NULLIF(TRIM(COALESCE(p_custom_domain, '')), ''),
    TRIM(COALESCE(p_phone, '')),
    TRIM(COALESCE(p_address, '')),
    TRIM(COALESCE(p_instagram, '')),
    COALESCE(NULLIF(TRIM(p_primary_color), ''), '#d86a1a'),
    TRUE
  )
  RETURNING id INTO v_restaurant_id;

  -- 2. Dükkan Ayarları (store_settings) Başlangıç Satırı Ekle
  INSERT INTO public.store_settings (
    id,
    order_mode,
    status_message,
    weekly_hours,
    online_discount_enabled,
    online_discount_percent,
    payment_methods,
    updated_at
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
    'is_active', TRUE
  );
END;
$$;

-- 3. Restoran Durumunu Değiştir (Aktif / Pasif)
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

-- 4. Restoranı ve İlişkili Tüm Verilerini Kalıcı Olarak Sil (Korumalı)
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
  IF v_slug = '' OR v_slug = 'ginger-pizza' THEN
    RAISE EXCEPTION 'Ana referans restoran (ginger-pizza) silinemez!';
  END IF;

  SELECT id INTO v_rest_id FROM public.restaurants WHERE slug = v_slug;
  IF v_rest_id IS NULL THEN
    RAISE EXCEPTION 'Silinecek restoran bulunamadı: %', v_slug;
  END IF;

  -- 1. Sipariş ve müşteri verilerini temizle
  DELETE FROM public.order_items oi
  USING public.orders o
  WHERE oi.order_id = o.id
    AND COALESCE(NULLIF(TRIM(o.restaurant_slug), ''), 'ginger-pizza') = v_slug;

  DELETE FROM public.orders
  WHERE COALESCE(NULLIF(TRIM(restaurant_slug), ''), 'ginger-pizza') = v_slug;
  GET DIAGNOSTICS v_deleted_orders = ROW_COUNT;

  DELETE FROM public.customers
  WHERE COALESCE(NULLIF(TRIM(restaurant_slug), ''), 'ginger-pizza') = v_slug;
  GET DIAGNOSTICS v_deleted_customers = ROW_COUNT;

  -- 2. Dükkan ayarları
  DELETE FROM public.store_settings WHERE id = v_slug;

  -- 3. Restoran kaydı (CASCADE ile categories, menu_items, item_variants otomatik silinir)
  DELETE FROM public.restaurants WHERE id = v_rest_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'deleted_slug', v_slug,
    'deleted_orders', v_deleted_orders,
    'deleted_customers', v_deleted_customers
  );
END;
$$;

-- 5. Restoran Listesini Özet Verilerle Getir
CREATE OR REPLACE FUNCTION public.get_platform_restaurants_summary()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
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
      r.is_active,
      r.created_at,
      (SELECT COUNT(*)::INT FROM public.menu_items mi WHERE mi.restaurant_id = r.id) AS menu_items_count,
      (SELECT COUNT(*)::INT FROM public.orders o WHERE COALESCE(NULLIF(TRIM(o.restaurant_slug), ''), 'ginger-pizza') = r.slug) AS total_orders_count,
      (SELECT COALESCE(SUM(o.total_amount), 0)::NUMERIC(10,2) FROM public.orders o WHERE COALESCE(NULLIF(TRIM(o.restaurant_slug), ''), 'ginger-pizza') = r.slug AND o.status <> 'cancelled') AS total_revenue
    FROM public.restaurants r
    ORDER BY (r.slug = 'ginger-pizza') DESC, r.created_at ASC
  ) row_data;

  RETURN v_result;
END;
$$;

-- Anon ve Authenticated rollere çalıştırma yetkisi ver
GRANT EXECUTE ON FUNCTION public.slugify_restaurant_name(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_restaurant_with_defaults(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_restaurant_status(TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_restaurant_permanently(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_platform_restaurants_summary() TO anon, authenticated;

-- 6. Restoran Bilgilerini & Özel Domaini Güncelle
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
      custom_domain = NULLIF(v_clean_domain, ''),
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

GRANT EXECUTE ON FUNCTION public.update_restaurant_details(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- Master Panel için restaurants tablosuna anon okuma/güncelleme/ekleme politikaları (güvenlik için kontrol)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'restaurants' AND policyname = 'restaurants_master_all'
  ) THEN
    CREATE POLICY "restaurants_master_all"
      ON public.restaurants
      FOR ALL
      TO anon, authenticated
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;
