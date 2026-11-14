-- ==============================================================================
-- XUBO / GINGER PIZZA - ÇOK KİRACILI (MULTI-TENANT) PROFİL & KANAL İZOLASYONU
-- ==============================================================================
-- Supabase Dashboard -> SQL Editor üzerinden çalıştırın.
-- Ne yapar:
--   1. restaurants tablosuna profile (JSONB) sütunu ekler.
--   2. anon okuma yetkisine sadece genel profile sütununu dahil eder (admin_email/password kapalı kalır).
--   3. ginger-pizza ve we-smash-the-burger için kendi WhatsApp ve sipariş kanalı linklerini tanımlar.
--      Diğer restoranlar varsayılan '{}' kalır (hiçbirine Ginger linki sızmaz).
-- ==============================================================================

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS profile JSONB NOT NULL DEFAULT '{}'::jsonb;

REVOKE SELECT ON public.restaurants FROM anon;
GRANT SELECT (
  id, name, slug, custom_domain, phone, address, instagram,
  primary_color, is_active, created_at, updated_at, profile
) ON public.restaurants TO anon;

UPDATE public.restaurants
SET
  profile = jsonb_build_object(
    'whatsapp', '905536660201',
    'whatsapp_display', '0553 666 02 01',
    'channels', jsonb_build_object(
      'trendyol', 'https://tgoyemek.com/restoranlar/1152',
      'yemeksepeti', 'https://www.yemeksepeti.com/restaurant/depv/ginger-pizza',
      'migros', 'https://www.migros.com.tr/yemek/ginger-pizza-kadikoy-goztepe-mah-st-18b72'
    )
  ),
  updated_at = NOW()
WHERE slug = 'ginger-pizza';

UPDATE public.restaurants
SET
  profile = jsonb_build_object(
    'whatsapp', '',
    'whatsapp_display', '',
    'channels', jsonb_build_object(
      'yemeksepeti', 'https://www.yemeksepeti.com/restaurant/rcqj/we-smash-the-burger'
    )
  ),
  updated_at = NOW()
WHERE slug = 'we-smash-the-burger';
