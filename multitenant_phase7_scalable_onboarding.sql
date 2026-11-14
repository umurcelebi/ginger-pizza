-- ==============================================================================
-- XUBO / GINGER PIZZA - FAZ 7: ÖLÇEKLENEBİLİR RESTORAN EKLEME (ZERO-TOUCH ONBOARDING),
-- OTOMATİK AUTH KULLANICI KURULUMU, MAĞAZA BAZLI SİPARİŞ NO VE PERFORMANS İNDEKSLERİ
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Ne yapar:
--   1. provision_or_reset_restaurant_admin(p_slug, p_new_password):
--      Mağaza yöneticisi için auth.users + auth.identities kaydını (ve app_metadata
--      izolasyon etiketlerini) otomatik oluşturur veya şifresini sıfırlar.
--   2. create_restaurant_with_defaults():
--      Yeni restoran açıldığında restaurants + store_settings + başlangıç kategorileri
--      + Supabase Auth (auth.users) hesabını tek adımda kurar ve üretilen şifreyi döner.
--   3. delete_restaurant_permanently():
--      Mağaza silindiğinde o mağazaya ait auth.users hesabını da temizler.
--   4. assign_tenant_order_number() (BEFORE INSERT trigger):
--      Sipariş numaralarını (order_number) global sayaç yerine her mağaza için
--      bağımsız (1001, 1002...) ilerletir; mağazalar arası sipariş hacmi sızıntısını önler.
--   5. Çoklu restoran ölçekleme indeksleri ve tek sorguluk get_platform_restaurants_summary()
--      optimizasyonunu uygular.
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 1. Mağaza Yöneticisi Auth Hesabı Otomatik Kurulum / Şifre Sıfırlama RPC'si
CREATE OR REPLACE FUNCTION public.provision_or_reset_restaurant_admin(
  p_slug TEXT,
  p_new_password TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_slug TEXT := LOWER(TRIM(COALESCE(p_slug, '')));
  v_restaurant RECORD;
  v_cred_slug TEXT;
  v_admin_email TEXT;
  v_password TEXT;
  v_user_id UUID;
  v_existing_role TEXT;
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Sadece super_admin mağaza yönetici şifresi oluşturabilir veya sıfırlayabilir.';
  END IF;

  IF v_slug = '' THEN
    RAISE EXCEPTION 'INVALID_SLUG: Restoran slug boş olamaz.';
  END IF;

  SELECT id, name, slug, admin_email
  INTO v_restaurant
  FROM public.restaurants
  WHERE slug = v_slug
  LIMIT 1;

  IF v_restaurant.id IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_NOT_FOUND: Restoran bulunamadı (%).', v_slug;
  END IF;

  v_cred_slug := REGEXP_REPLACE(LOWER(v_restaurant.slug), '[^a-z0-9]', '', 'g');
  IF v_cred_slug = '' THEN
    v_cred_slug := 'restoran';
  END IF;

  v_admin_email := LOWER(TRIM(COALESCE(NULLIF(TRIM(v_restaurant.admin_email), ''), 'admin@' || v_cred_slug || '.com')));

  -- Şifre belirtilmemişse okunabilir, güçlü 10 karakterli rastgele şifre üret
  v_password := NULLIF(TRIM(COALESCE(p_new_password, '')), '');
  IF v_password IS NULL THEN
    v_password := SUBSTR(REPLACE(REPLACE(REPLACE(ENCODE(gen_random_bytes(9), 'base64'), '/', 'x'), '+', 'y'), '=', ''), 1, 8) || '9!';
  END IF;

  IF LENGTH(v_password) < 6 THEN
    RAISE EXCEPTION 'WEAK_PASSWORD: Şifre en az 6 karakter olmalıdır.';
  END IF;

  -- restaurants tablosunda admin_email'i güncel tut, düz metin şifreyi her zaman NULL yap
  UPDATE public.restaurants
  SET admin_email = v_admin_email,
      admin_password = NULL,
      updated_at = NOW()
  WHERE id = v_restaurant.id;

  -- Eksik başlangıç kategorisi varsa otomatik tamamla (örn. önceden açılmış boş mağazalar için)
  IF NOT EXISTS (SELECT 1 FROM public.categories WHERE restaurant_id = v_restaurant.id) THEN
    INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
    VALUES
      (v_restaurant.id, 'ana-urunler', 'Ana Ürünler', 1),
      (v_restaurant.id, 'menuler', 'Menüler', 2),
      (v_restaurant.id, 'yan-urunler', 'Yan Ürünler & Soslar', 3),
      (v_restaurant.id, 'icecekler', 'İçecekler & Tatlılar', 4)
    ON CONFLICT DO NOTHING;
  END IF;

  -- auth.users içinde mevcut kullanıcıyı kontrol et
  SELECT id, COALESCE(raw_app_meta_data ->> 'role', '')
  INTO v_user_id, v_existing_role
  FROM auth.users
  WHERE LOWER(email) = v_admin_email
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    IF v_existing_role = 'super_admin' THEN
      RAISE EXCEPTION 'FORBIDDEN_TARGET: Super admin hesabı mağaza hesabına dönüştürülemez.';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(v_password, gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
        raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
          'provider', 'email',
          'providers', jsonb_build_array('email'),
          'role', 'restaurant_admin',
          'restaurant_slug', v_restaurant.slug,
          'restaurant_id', v_restaurant.id::text
        ),
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'restaurant_slug', v_restaurant.slug,
          'restaurant_name', v_restaurant.name
        ),
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change = COALESCE(email_change, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        phone_change = COALESCE(phone_change, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        updated_at = NOW()
    WHERE id = v_user_id;
  ELSE
    v_user_id := gen_random_uuid();

    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change,
      email_change_token_current,
      reauthentication_token,
      phone_change,
      phone_change_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000'::uuid,
      v_user_id,
      'authenticated',
      'authenticated',
      v_admin_email,
      crypt(v_password, gen_salt('bf')),
      NOW(),
      jsonb_build_object(
        'provider', 'email',
        'providers', jsonb_build_array('email'),
        'role', 'restaurant_admin',
        'restaurant_slug', v_restaurant.slug,
        'restaurant_id', v_restaurant.id::text
      ),
      jsonb_build_object(
        'restaurant_slug', v_restaurant.slug,
        'restaurant_name', v_restaurant.name
      ),
      FALSE,
      NOW(),
      NOW(),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      ''
    );
  END IF;

  -- auth.identities kaydı yoksa ekle
  IF NOT EXISTS (
    SELECT 1 FROM auth.identities
    WHERE user_id = v_user_id AND provider = 'email'
  ) THEN
    INSERT INTO auth.identities (
      id,
      user_id,
      provider_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_user_id,
      v_user_id::text,
      jsonb_build_object(
        'sub', v_user_id::text,
        'email', v_admin_email,
        'email_verified', TRUE,
        'phone_verified', FALSE
      ),
      'email',
      NOW(),
      NOW(),
      NOW()
    );
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'restaurant_id', v_restaurant.id,
    'slug', v_restaurant.slug,
    'name', v_restaurant.name,
    'user_id', v_user_id,
    'admin_email', v_admin_email,
    'admin_password', v_password
  );
END;
$$;

REVOKE ALL ON FUNCTION public.provision_or_reset_restaurant_admin(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provision_or_reset_restaurant_admin(TEXT, TEXT) TO authenticated;


-- 2. create_restaurant_with_defaults() — Zero-Touch Onboarding (Auth Dahil)
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
SET search_path = public, extensions
AS $$
DECLARE
  v_clean_name TEXT := TRIM(COALESCE(p_name, ''));
  v_slug TEXT;
  v_restaurant_id UUID;
  v_count INT := 0;
  v_base_slug TEXT;
  v_cred_slug TEXT;
  v_admin_email TEXT;
  v_auth_result JSONB;
  v_admin_password TEXT;
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

  INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
  VALUES
    (v_restaurant_id, 'ana-urunler', 'Ana Ürünler', 1),
    (v_restaurant_id, 'menuler', 'Menüler', 2),
    (v_restaurant_id, 'yan-urunler', 'Yan Ürünler & Soslar', 3),
    (v_restaurant_id, 'icecekler', 'İçecekler & Tatlılar', 4)
  ON CONFLICT DO NOTHING;

  -- Supabase Auth kullanıcısını ve app_metadata yetkilerini otomatik kur
  v_auth_result := public.provision_or_reset_restaurant_admin(v_slug, NULL);
  v_admin_password := v_auth_result ->> 'admin_password';

  RETURN jsonb_build_object(
    'success', TRUE,
    'id', v_restaurant_id,
    'name', v_clean_name,
    'slug', v_slug,
    'admin_email', v_admin_email,
    'admin_password', v_admin_password,
    'suggested_temp_password', v_admin_password,
    'is_active', TRUE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_restaurant_with_defaults(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_restaurant_with_defaults(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- 3. delete_restaurant_permanently() — Auth kullanıcısını da temizle
CREATE OR REPLACE FUNCTION public.delete_restaurant_permanently(p_slug TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := LOWER(TRIM(COALESCE(p_slug, '')));
  v_rest_id UUID;
  v_deleted_orders INT := 0;
  v_deleted_customers INT := 0;
  v_deleted_auth_users INT := 0;
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

  -- Silinen mağazanın yönetici auth hesabını temizle (super_admin hariç)
  DELETE FROM auth.users
  WHERE (
    LOWER(COALESCE(raw_app_meta_data ->> 'restaurant_slug', '')) = v_slug
    OR COALESCE(raw_app_meta_data ->> 'restaurant_id', '') = v_rest_id::text
  )
  AND COALESCE(raw_app_meta_data ->> 'role', '') <> 'super_admin';
  GET DIAGNOSTICS v_deleted_auth_users = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', TRUE,
    'deleted_slug', v_slug,
    'deleted_orders', v_deleted_orders,
    'deleted_customers', v_deleted_customers,
    'deleted_auth_users', v_deleted_auth_users
  );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_restaurant_permanently(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_restaurant_permanently(TEXT) TO authenticated;


-- 4. Mağaza Bazlı İzole Sipariş Numarası (Per-Tenant Sequential order_number)
CREATE OR REPLACE FUNCTION public.assign_tenant_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next_num INTEGER;
BEGIN
  IF NEW.restaurant_slug IS NULL OR TRIM(NEW.restaurant_slug) = '' THEN
    RAISE EXCEPTION 'RESTAURANT_SLUG_REQUIRED: Sipariş için restaurant_slug zorunludur.';
  END IF;

  -- Aynı mağazaya aynı milisaniyede gelen siparişlerin sıra numarası çakışmasını önler,
  -- farklı mağazaları birbirinden tamamen bağımsız tutar.
  PERFORM pg_advisory_xact_lock(hashtext('order_num:' || NEW.restaurant_slug));

  SELECT COALESCE(MAX(order_number), 1000) + 1
  INTO v_next_num
  FROM public.orders
  WHERE restaurant_slug = NEW.restaurant_slug;

  NEW.order_number := v_next_num;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_tenant_order_number ON public.orders;
CREATE TRIGGER trg_assign_tenant_order_number
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_tenant_order_number();


-- 5. Çoklu Restoran (100+ Mağaza) Performans İndeksleri
CREATE INDEX IF NOT EXISTS idx_orders_slug_status_created
  ON public.orders (restaurant_slug, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_slug_order_number
  ON public.orders (restaurant_slug, order_number DESC);

CREATE INDEX IF NOT EXISTS idx_orders_slug_created_at
  ON public.orders (restaurant_slug, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant_id_cat
  ON public.menu_items (restaurant_id, category_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_categories_restaurant_id_sort
  ON public.categories (restaurant_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_customers_slug_spent
  ON public.customers (restaurant_slug, total_spent DESC);


-- 6. get_platform_restaurants_summary() — Tek Sorguluk (CTE JOIN) Ölçeklenebilir Versiyon
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

  WITH menu_stats AS (
    SELECT
      restaurant_id,
      COUNT(*)::INT AS menu_items_count
    FROM public.menu_items
    GROUP BY restaurant_id
  ),
  order_stats AS (
    SELECT
      restaurant_slug,
      COUNT(*)::INT AS total_orders_count,
      COALESCE(SUM(total_amount) FILTER (WHERE status <> 'cancelled'), 0)::NUMERIC(10,2) AS total_revenue,
      MAX(created_at) AS last_order_at
    FROM public.orders
    GROUP BY restaurant_slug
  ),
  auth_stats AS (
    SELECT DISTINCT
      LOWER(COALESCE(raw_app_meta_data ->> 'restaurant_slug', '')) AS restaurant_slug
    FROM auth.users
    WHERE COALESCE(raw_app_meta_data ->> 'restaurant_slug', '') <> ''
  )
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
      (au.restaurant_slug IS NOT NULL) AS has_auth_user,
      r.is_active,
      r.created_at,
      COALESCE(ms.menu_items_count, 0) AS menu_items_count,
      COALESCE(os.total_orders_count, 0) AS total_orders_count,
      COALESCE(os.total_revenue, 0)::NUMERIC(10,2) AS total_revenue,
      os.last_order_at
    FROM public.restaurants r
    LEFT JOIN menu_stats ms ON ms.restaurant_id = r.id
    LEFT JOIN order_stats os ON os.restaurant_slug = r.slug
    LEFT JOIN auth_stats au ON au.restaurant_slug = LOWER(r.slug)
    ORDER BY (r.slug = 'ginger-pizza') DESC, r.created_at ASC
  ) row_data;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_platform_restaurants_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_platform_restaurants_summary() TO authenticated;


-- 7. Mevcut kategorisiz restoranlara (örn. pizza-art) varsayılan başlangıç kategorilerini ekle
INSERT INTO public.categories (restaurant_id, slug, name, sort_order)
SELECT r.id, c.slug, c.name, c.sort_order
FROM public.restaurants r
CROSS JOIN (
  VALUES
    ('ana-urunler', 'Ana Ürünler', 1),
    ('menuler', 'Menüler', 2),
    ('yan-urunler', 'Yan Ürünler & Soslar', 3),
    ('icecekler', 'İçecekler & Tatlılar', 4)
) AS c(slug, name, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.categories existing WHERE existing.restaurant_id = r.id
)
ON CONFLICT DO NOTHING;
