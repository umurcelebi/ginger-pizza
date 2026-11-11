-- ============================================================================
-- GINGER PIZZA & MULTI-TENANT RESTAURANT PLATFORM
-- Supabase PostgreSQL Schema & Seed Data
-- ============================================================================

-- 1. Eklentiler
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Restoranlar Tablosu
CREATE TABLE IF NOT EXISTS public.restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    custom_domain TEXT UNIQUE,
    phone TEXT,
    address TEXT,
    instagram TEXT,
    primary_color TEXT DEFAULT '#d86a1a',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Kategoriler Tablosu
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Menü Ürünleri Tablosu
CREATE TABLE IF NOT EXISTS public.menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    badge TEXT,
    badge_type TEXT DEFAULT 'popular', -- 'signature', 'popular', 'veg', 'gourmet'
    is_available BOOLEAN DEFAULT TRUE,
    is_pizza BOOLEAN DEFAULT TRUE,
    fixed_price NUMERIC(10, 2), -- Pizza olmayan ürünler için sabit porsiyon fiyatı
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Pizza Boyut ve Fiyat Çeşitleri
CREATE TABLE IF NOT EXISTS public.item_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id UUID REFERENCES public.menu_items(id) ON DELETE CASCADE,
    size_key TEXT NOT NULL, -- 'small', 'medium', 'xlarge'
    size_label TEXT NOT NULL, -- 'Small (26 cm)', 'Medium (32 cm)', 'X-Large (42 cm)'
    price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- GÜVENLİK VE ROW LEVEL SECURITY (RLS) POLİTİKALARI
-- ============================================================================

ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_variants ENABLE ROW LEVEL SECURITY;

-- Herkes (müşteriler/ziyaretçiler) aktif restoran ve menüyü okuyabilir
CREATE POLICY "Public read restaurants" ON public.restaurants FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Public read categories" ON public.categories FOR SELECT USING (TRUE);
CREATE POLICY "Public read menu_items" ON public.menu_items FOR SELECT USING (TRUE);
CREATE POLICY "Public read item_variants" ON public.item_variants FOR SELECT USING (TRUE);

-- Giriş yapmış kullanıcılar (Restoran Adminleri) menü üzerinde işlem yapabilir
CREATE POLICY "Auth write menu_items" ON public.menu_items FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Auth write item_variants" ON public.item_variants FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "Auth write categories" ON public.categories FOR ALL USING (auth.role() = 'authenticated');

-- ============================================================================
-- BAŞLANGIÇ VERİLERİ (GINGER PIZZA SEED)
-- ============================================================================

DO $$
DECLARE
    v_rest_id UUID;
    v_cat_imza UUID;
    v_cat_klasik UUID;
    v_cat_gurme UUID;
    v_cat_veg UUID;
    v_cat_yan UUID;
    v_cat_tatli UUID;
    v_item_id UUID;
BEGIN
    -- Restoran Ekle
    INSERT INTO public.restaurants (name, slug, custom_domain, phone, address, instagram, primary_color)
    VALUES (
        'Ginger Pizza',
        'ginger-pizza',
        'www.gingerpizza.com',
        '0216 337 02 01',
        'Göztepe Mah. Rıdvanpaşa Sokak No: 16, Kadıköy / İstanbul',
        '@gingerpizza',
        '#d86a1a'
    ) RETURNING id INTO v_rest_id;

    -- Kategorileri Ekle
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'İmza Pizzalar', 'imza', 1) RETURNING id INTO v_cat_imza;
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'Klasik Lezzetler', 'klasik', 2) RETURNING id INTO v_cat_klasik;
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'Gurme & Şarküteri', 'gurme', 3) RETURNING id INTO v_cat_gurme;
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'Vejetaryen & Mantarlı', 'vejetaryen', 4) RETURNING id INTO v_cat_veg;
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'Yan Lezzetler & Soslar', 'yan-urun', 5) RETURNING id INTO v_cat_yan;
    INSERT INTO public.categories (restaurant_id, name, slug, sort_order) VALUES (v_rest_id, 'Tatlı & İçecek', 'tatli-icecek', 6) RETURNING id INTO v_cat_tatli;

    -- 1. Ginger Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_imza, 'Ginger Pizza', 'Mozzarella peyniri, domates sos, dana bacon, karamelize soğan, özel cheddar sos, barbekü sos.', 'İmza Lezzet', 'signature', TRUE, 1) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 435), (v_item_id, 'medium', 'Medium (32 cm)', 590), (v_item_id, 'xlarge', 'X-Large (42 cm)', 980);

    -- 2. Banner Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Banner Pizza', 'Mozzarella peyniri, domates sos, taze dilim domates, ev yapımı fesleğen sos.', 'Popüler', 'popular', TRUE, 2) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 390), (v_item_id, 'medium', 'Medium (32 cm)', 500), (v_item_id, 'xlarge', 'X-Large (42 cm)', 790);

    -- 3. Montana Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_klasik, 'Montana Pizza', 'Mozzarella peyniri, domates sos, fermente dana sucuk, kültür mantarı, siyah dilimli zeytin.', 'Geleneksel', 'popular', TRUE, 3) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 420), (v_item_id, 'medium', 'Medium (32 cm)', 570), (v_item_id, 'xlarge', 'X-Large (42 cm)', 925);

    -- 4. Floki Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Floki Pizza', 'Mozzarella peyniri, domates sos, dana bacon, rokfor peyniri (blue cheese), taze istiridye mantarı.', 'Gurme Seçim', 'signature', TRUE, 4) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 480), (v_item_id, 'medium', 'Medium (32 cm)', 660), (v_item_id, 'xlarge', 'X-Large (42 cm)', 1050);

    -- 5. Ragnar Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_gurme, 'Ragnar Pizza', 'Mozzarella peyniri, domates sos, hakiki Rize kavurma, hellim peyniri, közlenmiş patlıcan, çeri domates.', 'Şefin Spesiyali', 'signature', TRUE, 5) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 495), (v_item_id, 'medium', 'Medium (32 cm)', 690), (v_item_id, 'xlarge', 'X-Large (42 cm)', 1110);

    -- 6. Garner Pizza
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, sort_order)
    VALUES (v_rest_id, v_cat_veg, 'Garner Pizza', 'Mozzarella peyniri, domates sos, kültür mantarı, taze kestane mantarı, istiridye mantarı, dağ kekiği.', '3 Mantarlı', 'veg', TRUE, 6) RETURNING id INTO v_item_id;
    INSERT INTO public.item_variants (item_id, size_key, size_label, price) VALUES (v_item_id, 'small', 'Small (26 cm)', 420), (v_item_id, 'medium', 'Medium (32 cm)', 560), (v_item_id, 'xlarge', 'X-Large (42 cm)', 890);

    -- 7. Yan Ürün: Fırın Patates
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_yan, 'Baharatlı Elma Dilim Fırın Patates (300 gr)', 'Zeytinyağı, kaya tuzu, kekik, tatlı toz kırmızı biber ile fırınlanmış patates.', 'Fırından', 'gourmet', FALSE, 265, 7);

    -- 8. Tatlı: Çikolatalı Sufle
    INSERT INTO public.menu_items (restaurant_id, category_id, name, description, badge, badge_type, is_pizza, fixed_price, sort_order)
    VALUES (v_rest_id, v_cat_tatli, 'Taş Fırında Çikolatalı Sufle', 'İçi akışkan Belçika çikolatalı sıcak fırın sufle, pudra şekeri ile.', 'Tatlı', 'signature', FALSE, 220, 8);
END $$;
