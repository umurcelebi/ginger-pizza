-- ============================================================================
-- GINGER PIZZA SİPARİŞ & KARŞILAMA SİSTEMİ (ORDERS SCHEMA)
-- ============================================================================

-- 1. Siparişler Ana Tablosu
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number SERIAL,
    customer_name TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    delivery_type TEXT NOT NULL DEFAULT 'delivery', -- 'delivery' (Paket Servis) veya 'takeaway' (Gel-Al)
    delivery_address TEXT,
    order_notes TEXT,
    payment_method TEXT NOT NULL DEFAULT 'door_card', -- 'door_card' (Kapıda Kart), 'door_cash' (Kapıda Nakit)
    total_amount NUMERIC(10, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'new', -- 'new', 'preparing', 'on_way', 'delivered', 'cancelled'
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Sipariş Kalemleri Tablosu
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    item_name TEXT NOT NULL,
    size_label TEXT,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(10, 2) NOT NULL,
    total_price NUMERIC(10, 2) NOT NULL,
    item_notes TEXT
);

-- 3. RLS Güvenlik Politikaları
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- Müşterilerin sipariş oluşturmasına ve siparişlerini takip etmesine izin ver
CREATE POLICY "Public insert orders" ON public.orders FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Public insert order_items" ON public.order_items FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "Public read orders" ON public.orders FOR SELECT USING (TRUE);
CREATE POLICY "Public read order_items" ON public.order_items FOR SELECT USING (TRUE);
CREATE POLICY "Public update orders" ON public.orders FOR UPDATE USING (TRUE);
CREATE POLICY "Public update order_items" ON public.order_items FOR UPDATE USING (TRUE);

-- 4. Realtime Bildirimlerini Etkinleştir (Mutfak Ekranı Canlı Düşmesi İçin)
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;

-- 5. Mevcut Tablo İçin Gün Sonu Arşivleme Sütunu (Zaten kuruluysa sadece bunu çalıştırın)
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;
