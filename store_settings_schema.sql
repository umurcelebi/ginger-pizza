-- ============================================================================
-- GINGER PIZZA — ÇALIŞMA SAATLERİ, MANUEL KAPATMA VE YOĞUN MODU ŞEMASI
-- Supabase SQL Editor üzerinden çalıştırın.
-- ============================================================================

-- 1. Dükkan Durum & Haftalık Saatler Tablosu
CREATE TABLE IF NOT EXISTS public.store_settings (
    id TEXT PRIMARY KEY DEFAULT 'ginger-pizza',
    order_mode TEXT NOT NULL DEFAULT 'auto' CHECK (order_mode IN ('auto', 'busy', 'manual_open', 'manual_closed')),
    busy_until TIMESTAMPTZ,
    status_message TEXT DEFAULT '',
    weekly_hours JSONB NOT NULL DEFAULT '{
      "1": {"enabled": true, "open": "11:30", "close": "23:00"},
      "2": {"enabled": true, "open": "11:30", "close": "23:00"},
      "3": {"enabled": true, "open": "11:30", "close": "23:00"},
      "4": {"enabled": true, "open": "11:30", "close": "23:00"},
      "5": {"enabled": true, "open": "11:30", "close": "23:00"},
      "6": {"enabled": true, "open": "11:30", "close": "23:00"},
      "0": {"enabled": true, "open": "11:30", "close": "23:00"}
    }'::jsonb,
    online_discount_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    online_discount_percent NUMERIC(5, 2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Önceden oluşturulmuş tablolar için order_mode ve online indirim sütunlarını güncelle
ALTER TABLE public.store_settings DROP CONSTRAINT IF EXISTS store_settings_order_mode_check;
ALTER TABLE public.store_settings
    ADD CONSTRAINT store_settings_order_mode_check
    CHECK (order_mode IN ('auto', 'busy', 'manual_open', 'manual_closed'));

ALTER TABLE public.store_settings
    ADD COLUMN IF NOT EXISTS online_discount_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.store_settings
    ADD COLUMN IF NOT EXISTS online_discount_percent NUMERIC(5, 2) NOT NULL DEFAULT 0;

-- Siparişler tablosuna ara toplam / online indirim sütunları ekle
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS subtotal_amount NUMERIC(10, 2);
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5, 2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10, 2) NOT NULL DEFAULT 0;

-- Başlangıç satırı (varsa dokunma)
INSERT INTO public.store_settings (id)
VALUES ('ginger-pizza')
ON CONFLICT (id) DO NOTHING;

-- 2. RLS Politikaları
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read store_settings" ON public.store_settings;
CREATE POLICY "Public read store_settings" ON public.store_settings FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS "Public insert store_settings" ON public.store_settings;
CREATE POLICY "Public insert store_settings" ON public.store_settings FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Public update store_settings" ON public.store_settings;
CREATE POLICY "Public update store_settings" ON public.store_settings FOR UPDATE USING (TRUE);

-- 3. Realtime Yayını
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.store_settings;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- 4. Veritabanı Seviyesinde Sipariş Engelleme Trigger'ı (Europe/Istanbul Saat Dilimi)
CREATE OR REPLACE FUNCTION public.enforce_store_open_on_order()
RETURNS TRIGGER AS $$
DECLARE
    v_settings public.store_settings%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_tr TIMESTAMP := NOW() AT TIME ZONE 'Europe/Istanbul';
    v_cur_time TIME := v_tr::TIME;
    v_dow INT := EXTRACT(DOW FROM v_tr)::INT; -- 0 = Pazar .. 6 = Cumartesi
    v_prev_dow INT := (v_dow + 6) % 7;
    v_today JSONB;
    v_prev JSONB;
    v_open TIME;
    v_close TIME;
    v_prev_open TIME;
    v_prev_close TIME;
    v_is_open BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_settings FROM public.store_settings WHERE id = 'ginger-pizza' LIMIT 1;

    -- Henüz ayar satırı yoksa geriye dönük uyumluluk için izin ver
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- 1. Manuel Kapalı / Manuel Açık
    IF v_settings.order_mode = 'manual_closed' THEN
        RAISE EXCEPTION 'STORE_CLOSED: Dükkanımız şu anda online siparişe kapalıdır.';
    END IF;

    IF v_settings.order_mode = 'manual_open' THEN
        RETURN NEW;
    END IF;

    -- 2. Yoğun Modu (Süresiz veya süresi henüz dolmamışsa)
    IF v_settings.order_mode = 'busy' AND (v_settings.busy_until IS NULL OR v_settings.busy_until > v_now) THEN
        RAISE EXCEPTION 'STORE_BUSY: Yoğunluk nedeniyle online siparişlere geçici olarak ara verilmiştir.';
    END IF;

    -- 3. Bugünün Açılış / Kapanış Saatleri
    v_today := v_settings.weekly_hours -> (v_dow::TEXT);
    IF v_today IS NOT NULL AND COALESCE((v_today ->> 'enabled')::BOOLEAN, TRUE) THEN
        v_open := COALESCE(NULLIF(v_today ->> 'open', ''), '11:30')::TIME;
        v_close := COALESCE(NULLIF(v_today ->> 'close', ''), '23:00')::TIME;

        IF v_close > v_open THEN
            IF v_cur_time >= v_open AND v_cur_time < v_close THEN
                v_is_open := TRUE;
            END IF;
        ELSIF v_close < v_open THEN
            -- Gece yarısını aşan mesai (örn. 11:30 - 01:00)
            IF v_cur_time >= v_open THEN
                v_is_open := TRUE;
            END IF;
        END IF;
    END IF;

    -- Dün gece yarısını aşan mesai varsa bugünün ilk saatlerini de açık say
    IF NOT v_is_open THEN
        v_prev := v_settings.weekly_hours -> (v_prev_dow::TEXT);
        IF v_prev IS NOT NULL AND COALESCE((v_prev ->> 'enabled')::BOOLEAN, TRUE) THEN
            v_prev_open := COALESCE(NULLIF(v_prev ->> 'open', ''), '11:30')::TIME;
            v_prev_close := COALESCE(NULLIF(v_prev ->> 'close', ''), '23:00')::TIME;
            IF v_prev_close < v_prev_open AND v_cur_time < v_prev_close THEN
                v_is_open := TRUE;
            END IF;
        END IF;
    END IF;

    IF NOT v_is_open THEN
        RAISE EXCEPTION 'STORE_OUTSIDE_HOURS: Şu anda çalışma saatlerimiz dışındayız.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_store_open_on_order ON public.orders;
CREATE TRIGGER trg_enforce_store_open_on_order
    BEFORE INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_store_open_on_order();
