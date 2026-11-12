-- ============================================================================
-- Ginger Pizza & Çoklu Restoran — Raporlama, Müşteriler & Multi-Tenant Şema
-- ============================================================================
-- Supabase Free planında tek proje altında 3 restorana kadar izole kullanım için
-- restaurant_slug desteği ekler ve siparişlerden otomatik beslenen hafif
-- bir public.customers tablosu oluşturur. (Idempotent — tekrar çalıştırılabilir)

-- 1. ORDERS TABLOSUNA restaurant_slug & PERFORMANS İNDEKSİ EKLE
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS restaurant_slug TEXT NOT NULL DEFAULT 'ginger-pizza';

CREATE INDEX IF NOT EXISTS idx_orders_restaurant_created_at
  ON public.orders (restaurant_slug, created_at DESC);

-- 2. MAĞAZA AÇIK/KAPALI TRIGGER'INI ÇOKLU RESTORANA UYARLA
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
  target_slug := COALESCE(NULLIF(TRIM(NEW.restaurant_slug), ''), 'ginger-pizza');

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

DROP TRIGGER IF EXISTS trg_enforce_store_open_on_order ON public.orders;
CREATE TRIGGER trg_enforce_store_open_on_order
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.enforce_store_open_on_order();

-- 3. TELEFON NUMARASI NORMALİZASYON YARDIMCISI
CREATE OR REPLACE FUNCTION public.normalize_tr_phone(raw_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  digits TEXT;
BEGIN
  digits := regexp_replace(COALESCE(raw_phone, ''), '[^0-9]', '', 'g');
  IF digits = '' THEN
    RETURN '';
  END IF;
  IF length(digits) = 12 AND left(digits, 2) = '90' THEN
    digits := '0' || substr(digits, 3);
  ELSIF length(digits) = 10 AND left(digits, 1) = '5' THEN
    digits := '0' || digits;
  END IF;
  RETURN digits;
END;
$$;

-- 4. MÜŞTERİLER TABLOSU (Hafif / Tekil Müşteri Kaydı)
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  restaurant_slug TEXT NOT NULL DEFAULT 'ginger-pizza',
  phone_normalized TEXT NOT NULL,
  phone_display TEXT NOT NULL,
  customer_name TEXT NOT NULL,
  last_address TEXT DEFAULT '',
  order_count INTEGER NOT NULL DEFAULT 0,
  total_spent NUMERIC(12, 2) NOT NULL DEFAULT 0,
  last_order_at TIMESTAMPTZ,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (restaurant_slug, phone_normalized)
);

CREATE INDEX IF NOT EXISTS idx_customers_restaurant_spent
  ON public.customers (restaurant_slug, total_spent DESC);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read customers" ON public.customers;
CREATE POLICY "Public read customers" ON public.customers
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public insert customers" ON public.customers;
CREATE POLICY "Public insert customers" ON public.customers
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public update customers" ON public.customers;
CREATE POLICY "Public update customers" ON public.customers
  FOR UPDATE USING (true);

-- 5. SİPARİŞTEN OTOMATİK MÜŞTERİ SENKRONİZASYONU (INSERT & İPTAL GÜNCELLEME)
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

  slug := COALESCE(NULLIF(TRIM(NEW.restaurant_slug), ''), 'ginger-pizza');
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

DROP TRIGGER IF EXISTS trg_sync_customer_on_order ON public.orders;
CREATE TRIGGER trg_sync_customer_on_order
AFTER INSERT OR UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_customer_on_order();

-- 6. MEVCUT GEÇMİŞ SİPARİŞLERDEN TEK SEFERLİK MÜŞTERİ DOLDURMA (BACKFILL)
WITH ranked_orders AS (
  SELECT
    COALESCE(NULLIF(TRIM(restaurant_slug), ''), 'ginger-pizza') AS restaurant_slug,
    public.normalize_tr_phone(customer_phone) AS phone_normalized,
    customer_phone,
    customer_name,
    delivery_address,
    total_amount,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(NULLIF(TRIM(restaurant_slug), ''), 'ginger-pizza'), public.normalize_tr_phone(customer_phone)
      ORDER BY created_at DESC
    ) AS rn,
    MAX(CASE WHEN delivery_address IS NOT NULL AND TRIM(delivery_address) <> '' AND delivery_address <> 'Gel-Al Siparişi' THEN delivery_address ELSE NULL END)
      OVER (PARTITION BY COALESCE(NULLIF(TRIM(restaurant_slug), ''), 'ginger-pizza'), public.normalize_tr_phone(customer_phone)) AS latest_valid_addr
  FROM public.orders
  WHERE COALESCE(status, 'new') <> 'cancelled'
    AND public.normalize_tr_phone(customer_phone) <> ''
),
agg_customers AS (
  SELECT
    restaurant_slug,
    phone_normalized,
    MAX(CASE WHEN rn = 1 THEN customer_phone END) AS phone_display,
    MAX(CASE WHEN rn = 1 THEN customer_name END) AS customer_name,
    COALESCE(MAX(latest_valid_addr), MAX(CASE WHEN rn = 1 THEN delivery_address END), '') AS last_address,
    COUNT(*)::INT AS order_count,
    ROUND(COALESCE(SUM(total_amount), 0), 2) AS total_spent,
    MAX(created_at) AS last_order_at
  FROM ranked_orders
  GROUP BY restaurant_slug, phone_normalized
)
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
SELECT
  restaurant_slug,
  phone_normalized,
  COALESCE(NULLIF(TRIM(phone_display), ''), phone_normalized),
  COALESCE(NULLIF(TRIM(customer_name), ''), 'Müşteri'),
  last_address,
  order_count,
  total_spent,
  last_order_at,
  NOW()
FROM agg_customers
ON CONFLICT (restaurant_slug, phone_normalized) DO UPDATE
SET
  phone_display = EXCLUDED.phone_display,
  customer_name = EXCLUDED.customer_name,
  last_address = CASE
    WHEN NULLIF(TRIM(EXCLUDED.last_address), '') IS NOT NULL THEN EXCLUDED.last_address
    ELSE public.customers.last_address
  END,
  order_count = EXCLUDED.order_count,
  total_spent = EXCLUDED.total_spent,
  last_order_at = EXCLUDED.last_order_at,
  updated_at = NOW();

-- ============================================================================
-- 8. SATIŞ & MÜŞTERİ SIFIRLAMA POLİTİKALARI VE RPC (RESTORAN BAZLI)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'orders_anon_delete'
  ) THEN
    CREATE POLICY "orders_anon_delete"
      ON public.orders
      FOR DELETE
      TO anon, authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'order_items' AND policyname = 'order_items_anon_delete'
  ) THEN
    CREATE POLICY "order_items_anon_delete"
      ON public.order_items
      FOR DELETE
      TO anon, authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'customers' AND policyname = 'customers_anon_delete'
  ) THEN
    CREATE POLICY "customers_anon_delete"
      ON public.customers
      FOR DELETE
      TO anon, authenticated
      USING (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.reset_restaurant_history(
  p_restaurant_slug TEXT DEFAULT 'ginger-pizza'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT := COALESCE(NULLIF(TRIM(p_restaurant_slug), ''), 'ginger-pizza');
  v_deleted_order_items INTEGER := 0;
  v_deleted_orders INTEGER := 0;
  v_deleted_customers INTEGER := 0;
BEGIN
  DELETE FROM public.order_items oi
  USING public.orders o
  WHERE oi.order_id = o.id
    AND COALESCE(NULLIF(TRIM(o.restaurant_slug), ''), 'ginger-pizza') = v_slug;
  GET DIAGNOSTICS v_deleted_order_items = ROW_COUNT;

  DELETE FROM public.orders o
  WHERE COALESCE(NULLIF(TRIM(o.restaurant_slug), ''), 'ginger-pizza') = v_slug;
  GET DIAGNOSTICS v_deleted_orders = ROW_COUNT;

  DELETE FROM public.customers c
  WHERE COALESCE(NULLIF(TRIM(c.restaurant_slug), ''), 'ginger-pizza') = v_slug;
  GET DIAGNOSTICS v_deleted_customers = ROW_COUNT;

  RETURN jsonb_build_object(
    'restaurant_slug', v_slug,
    'deleted_order_items', v_deleted_order_items,
    'deleted_orders', v_deleted_orders,
    'deleted_customers', v_deleted_customers
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_restaurant_history(TEXT) TO anon, authenticated;

