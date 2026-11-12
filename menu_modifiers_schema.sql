-- ============================================================================
-- GINGER PIZZA — ÜRÜN EKLE / ÇIKAR / EK ÜRÜN VE SUPABASE YAZMA ŞEMASI
-- Supabase Dashboard -> SQL Editor üzerinden bir kez çalıştırın.
-- ============================================================================

-- 1. menu_items tablosuna modifiers (removals + additions) JSONB kolonu ekle
ALTER TABLE public.menu_items
ADD COLUMN IF NOT EXISTS modifiers JSONB NOT NULL DEFAULT '{"removals": [], "additions": []}'::jsonb;

-- 2. Admin panelinin Supabase'e doğrudan yazabilmesi için RLS politikaları
DROP POLICY IF EXISTS "Public write menu_items" ON public.menu_items;
CREATE POLICY "Public write menu_items"
    ON public.menu_items
    FOR ALL
    USING (TRUE)
    WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Public write item_variants" ON public.item_variants;
CREATE POLICY "Public write item_variants"
    ON public.item_variants
    FOR ALL
    USING (TRUE)
    WITH CHECK (TRUE);

-- 3. Tek tıkla tüm pizzalara ilave & ek ürün listesini kopyalayan RPC fonksiyonu
-- (Her pizzanın kendi 'removals' listesini korur, yalnızca 'additions' alanını günceller)
CREATE OR REPLACE FUNCTION public.copy_additions_to_all_pizzas(p_additions JSONB)
RETURNS INT AS $$
DECLARE
    v_updated_count INT;
BEGIN
    UPDATE public.menu_items
    SET
        modifiers = jsonb_set(
            COALESCE(modifiers, '{"removals": [], "additions": []}'::jsonb),
            '{additions}',
            COALESCE(p_additions, '[]'::jsonb),
            TRUE
        ),
        updated_at = NOW()
    WHERE is_pizza = TRUE;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
