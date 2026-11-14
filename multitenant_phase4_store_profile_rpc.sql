-- ==============================================================================
-- XUBO / GINGER PIZZA - FAZ 3: MAĞAZA YÖNETİCİSİ PROFİL GÜNCELLEME RPC'Sİ
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Her mağaza yöneticisinin (restaurant_admin) admin.html üzerinden YALNIZCA
-- kendi restoranının iletişim, WhatsApp, sipariş kanalları ve vitrin metinlerini
-- güvenli şekilde güncelleyebilmesini sağlar.
-- slug, custom_domain, is_active gibi platform alanlarına kesinlikle dokunmaz.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.update_my_restaurant_profile(
  p_restaurant_slug TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_instagram TEXT DEFAULT NULL,
  p_profile JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_auth_slug TEXT;
  v_req_slug TEXT;
  v_target_slug TEXT;
  v_existing RECORD;
  v_in JSONB;
  v_channels_in JSONB;
  v_channels_out JSONB := '{}'::jsonb;
  v_featured_in JSONB;
  v_featured_out JSONB := '{}'::jsonb;
  v_merged_profile JSONB;
  v_key TEXT;
  v_val TEXT;
  v_wa_digits TEXT;
  v_ig TEXT;
  v_allowed_text_keys TEXT[] := ARRAY[
    'logo_url',
    'whatsapp_display',
    'hero_tag',
    'hero_title_html',
    'hero_desc',
    'story_title',
    'story_desc',
    'menu_desc',
    'search_placeholder',
    'hub_banner_eyebrow',
    'hub_banner_desc',
    'hub_cta_label',
    'contact_title',
    'contact_desc',
    'hours_html',
    'footer_tagline',
    'footer_city',
    'footer_meta',
    'coming_eyebrow',
    'coming_title_html',
    'coming_desc',
    'coming_hours_html'
  ];
BEGIN
  v_role := public.auth_role();
  v_auth_slug := NULLIF(LOWER(TRIM(COALESCE(public.auth_restaurant_slug(), ''))), '');
  v_req_slug := NULLIF(LOWER(TRIM(COALESCE(p_restaurant_slug, ''))), '');

  IF public.is_super_admin() THEN
    v_target_slug := COALESCE(v_req_slug, v_auth_slug);
  ELSIF v_role = 'restaurant_admin' AND v_auth_slug IS NOT NULL THEN
    IF v_req_slug IS NOT NULL AND v_req_slug <> v_auth_slug THEN
      RAISE EXCEPTION 'FORBIDDEN_TENANT: Başka bir restoranın profilini güncelleyemezsiniz.';
    END IF;
    v_target_slug := v_auth_slug;
  ELSE
    RAISE EXCEPTION 'UNAUTHORIZED: Bu işlem için mağaza yöneticisi yetkisi gereklidir.';
  END IF;

  IF v_target_slug IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_SLUG_REQUIRED: Hedef restoran belirlenemedi.';
  END IF;

  SELECT id, slug, name, phone, address, instagram, profile
  INTO v_existing
  FROM public.restaurants
  WHERE slug = v_target_slug
  LIMIT 1;

  IF v_existing.id IS NULL THEN
    RAISE EXCEPTION 'RESTAURANT_NOT_FOUND: Restoran bulunamadı (%).', v_target_slug;
  END IF;

  v_in := CASE
    WHEN p_profile IS NOT NULL AND jsonb_typeof(p_profile) = 'object' THEN p_profile
    ELSE '{}'::jsonb
  END;

  -- Temel XSS / zararlı şema kontrolü
  IF v_in::TEXT ~* '(<script|javascript:|vbscript:|data:text/html|onerror=|onload=)' THEN
    RAISE EXCEPTION 'INVALID_INPUT: Güvenlik nedeniyle geçersiz içerik tespit edildi.';
  END IF;

  v_ig := TRIM(COALESCE(p_instagram, ''));
  IF v_ig ~* '^(javascript:|vbscript:|data:)' THEN
    RAISE EXCEPTION 'INVALID_URL: Geçersiz Instagram adresi.';
  END IF;

  v_merged_profile := COALESCE(v_existing.profile, '{}'::jsonb);

  -- İzin verilen metin alanlarını işle
  FOREACH v_key IN ARRAY v_allowed_text_keys
  LOOP
    IF v_in ? v_key THEN
      v_val := TRIM(COALESCE(v_in ->> v_key, ''));
      IF v_key = 'logo_url' AND v_val <> '' THEN
        IF NOT (v_val ~* '^https://' OR v_val ~* '^images/[a-zA-Z0-9._/-]+$') THEN
          RAISE EXCEPTION 'INVALID_URL: Logo URL yalnızca https:// veya images/... formatında olabilir.';
        END IF;
      END IF;
      IF v_val = '' THEN
        v_merged_profile := v_merged_profile - v_key;
      ELSE
        v_merged_profile := v_merged_profile || jsonb_build_object(v_key, v_val);
      END IF;
    END IF;
  END LOOP;

  -- WhatsApp numarası
  IF v_in ? 'whatsapp' THEN
    v_wa_digits := regexp_replace(COALESCE(v_in ->> 'whatsapp', ''), '[^0-9]', '', 'g');
    IF v_wa_digits = '' THEN
      v_merged_profile := v_merged_profile - 'whatsapp';
    ELSE
      v_merged_profile := v_merged_profile || jsonb_build_object('whatsapp', v_wa_digits);
    END IF;
  END IF;

  -- Sipariş kanalları (sadece https:// linkleri kabul edilir)
  IF v_in ? 'channels' AND jsonb_typeof(v_in -> 'channels') = 'object' THEN
    v_channels_in := v_in -> 'channels';
    FOREACH v_key IN ARRAY ARRAY['yemeksepeti', 'trendyol', 'migros', 'getir']
    LOOP
      v_val := TRIM(COALESCE(v_channels_in ->> v_key, ''));
      IF v_val <> '' THEN
        IF NOT (v_val ~* '^https://') THEN
          RAISE EXCEPTION 'INVALID_URL: % linki https:// ile başlamalıdır.', v_key;
        END IF;
        v_channels_out := v_channels_out || jsonb_build_object(v_key, v_val);
      END IF;
    END LOOP;
    v_merged_profile := v_merged_profile || jsonb_build_object('channels', v_channels_out);
  END IF;

  -- Öne çıkan vitrin kartı (featured)
  IF v_in ? 'featured' AND jsonb_typeof(v_in -> 'featured') = 'object' THEN
    v_featured_in := v_in -> 'featured';
    v_val := TRIM(COALESCE(v_featured_in ->> 'image', ''));
    IF v_val <> '' THEN
      IF NOT (v_val ~* '^https://' OR v_val ~* '^images/[a-zA-Z0-9._/-]+$') THEN
        RAISE EXCEPTION 'INVALID_URL: Öne çıkan görsel URL yalnızca https:// veya images/... formatında olabilir.';
      END IF;
      v_featured_out := v_featured_out || jsonb_build_object('image', v_val);
    END IF;
    FOREACH v_key IN ARRAY ARRAY['name', 'desc', 'pill']
    LOOP
      v_val := TRIM(COALESCE(v_featured_in ->> v_key, ''));
      IF v_val <> '' THEN
        v_featured_out := v_featured_out || jsonb_build_object(v_key, v_val);
      END IF;
    END LOOP;
    IF v_featured_out = '{}'::jsonb THEN
      v_merged_profile := v_merged_profile - 'featured';
    ELSE
      v_merged_profile := v_merged_profile || jsonb_build_object('featured', v_featured_out);
    END IF;
  END IF;

  UPDATE public.restaurants
  SET
    phone = CASE WHEN p_phone IS NOT NULL THEN TRIM(p_phone) ELSE phone END,
    address = CASE WHEN p_address IS NOT NULL THEN TRIM(p_address) ELSE address END,
    instagram = CASE WHEN p_instagram IS NOT NULL THEN v_ig ELSE instagram END,
    profile = v_merged_profile,
    updated_at = NOW()
  WHERE id = v_existing.id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'slug', v_existing.slug,
    'phone', CASE WHEN p_phone IS NOT NULL THEN TRIM(p_phone) ELSE v_existing.phone END,
    'address', CASE WHEN p_address IS NOT NULL THEN TRIM(p_address) ELSE v_existing.address END,
    'instagram', CASE WHEN p_instagram IS NOT NULL THEN v_ig ELSE v_existing.instagram END,
    'profile', v_merged_profile
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_restaurant_profile(TEXT, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_my_restaurant_profile(TEXT, TEXT, TEXT, TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.update_my_restaurant_profile(TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;
