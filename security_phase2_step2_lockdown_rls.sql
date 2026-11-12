-- ==============================================================================
-- XUBO / GINGER PIZZA - GÜVENLİK FAZ 2 (ADIM 2: RLS KİLİTLEME)
-- ==============================================================================
-- ÖNEMLİ: Bu scripti SADECE Adım 1 SQL çalıştırıldıktan, Auth kullanıcıları
-- oluşturulduktan ve yeni Auth girişli admin.html / orders.html / Master Panel
-- yayına alındıktan SONRA çalıştırın!
-- ==============================================================================

-- 1. RESTAURANTS: anon sadece güvenli genel sütunları okuyabilir (admin_password hariç)
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read active restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "Public insert restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "Public update restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "Public delete restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "Anon read active restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "Super admin manage restaurants" ON public.restaurants;

CREATE POLICY "Anon read active restaurants" ON public.restaurants
  FOR SELECT
  USING (
    is_active = TRUE
    OR public.is_super_admin()
    OR (public.auth_role() IN ('restaurant_admin', 'staff') AND slug = public.auth_restaurant_slug())
  );

CREATE POLICY "Super admin manage restaurants" ON public.restaurants
  FOR ALL
  TO authenticated
  USING (public.is_super_admin())
  WITH CHECK (public.is_super_admin());

REVOKE SELECT ON public.restaurants FROM anon;
GRANT SELECT (
  id, name, slug, custom_domain, phone, address, instagram,
  primary_color, is_active, created_at, updated_at, admin_email
) ON public.restaurants TO anon;

-- 2. CATEGORIES: Herkes menüyü okuyabilir; sadece restoran admini veya super_admin değiştirebilir
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read categories" ON public.categories;
DROP POLICY IF EXISTS "Public write categories" ON public.categories;
DROP POLICY IF EXISTS "Public insert categories" ON public.categories;
DROP POLICY IF EXISTS "Public update categories" ON public.categories;
DROP POLICY IF EXISTS "Public delete categories" ON public.categories;
DROP POLICY IF EXISTS "Admin manage categories" ON public.categories;

CREATE POLICY "Public read categories" ON public.categories
  FOR SELECT USING (TRUE);

CREATE POLICY "Admin manage categories" ON public.categories
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND restaurant_id = public.auth_restaurant_id())
  )
  WITH CHECK (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND restaurant_id = public.auth_restaurant_id())
  );

-- 3. MENU_ITEMS: Herkes menüyü okuyabilir; sadece restoran admini veya super_admin değiştirebilir
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Public write menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Public insert menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Public update menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Public delete menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Admin manage menu_items" ON public.menu_items;

CREATE POLICY "Public read menu_items" ON public.menu_items
  FOR SELECT USING (TRUE);

CREATE POLICY "Admin manage menu_items" ON public.menu_items
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND restaurant_id = public.auth_restaurant_id())
  )
  WITH CHECK (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND restaurant_id = public.auth_restaurant_id())
  );

-- 4. ITEM_VARIANTS: Herkes okuyabilir; sadece ilgili restoran admini veya super_admin değiştirebilir
ALTER TABLE public.item_variants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read item_variants" ON public.item_variants;
DROP POLICY IF EXISTS "Public write item_variants" ON public.item_variants;
DROP POLICY IF EXISTS "Public insert item_variants" ON public.item_variants;
DROP POLICY IF EXISTS "Public update item_variants" ON public.item_variants;
DROP POLICY IF EXISTS "Public delete item_variants" ON public.item_variants;
DROP POLICY IF EXISTS "Admin manage item_variants" ON public.item_variants;

CREATE POLICY "Public read item_variants" ON public.item_variants
  FOR SELECT USING (TRUE);

CREATE POLICY "Admin manage item_variants" ON public.item_variants
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (
      public.auth_role() = 'restaurant_admin'
      AND EXISTS (
        SELECT 1 FROM public.menu_items m
        WHERE m.id = item_id AND m.restaurant_id = public.auth_restaurant_id()
      )
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR (
      public.auth_role() = 'restaurant_admin'
      AND EXISTS (
        SELECT 1 FROM public.menu_items m
        WHERE m.id = item_id AND m.restaurant_id = public.auth_restaurant_id()
      )
    )
  );

-- 5. STORE_SETTINGS: Herkes okuyabilir (çalışma saati/indirim); sadece restoran admini veya super_admin değiştirebilir
ALTER TABLE public.store_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read store_settings" ON public.store_settings;
DROP POLICY IF EXISTS "Public insert store_settings" ON public.store_settings;
DROP POLICY IF EXISTS "Public update store_settings" ON public.store_settings;
DROP POLICY IF EXISTS "Public delete store_settings" ON public.store_settings;
DROP POLICY IF EXISTS "Admin manage store_settings" ON public.store_settings;

CREATE POLICY "Public read store_settings" ON public.store_settings
  FOR SELECT USING (TRUE);

CREATE POLICY "Admin manage store_settings" ON public.store_settings
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND id = public.auth_restaurant_slug())
  )
  WITH CHECK (
    public.is_super_admin()
    OR (public.auth_role() = 'restaurant_admin' AND id = public.auth_restaurant_slug())
  );

-- 6. ORDERS: Anon doğrudan okuyamaz/yazamz (create_validated_order & get_order_tracking RPC kullanır)
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read orders" ON public.orders;
DROP POLICY IF EXISTS "Public insert orders" ON public.orders;
DROP POLICY IF EXISTS "Public update orders" ON public.orders;
DROP POLICY IF EXISTS "Public delete orders" ON public.orders;
DROP POLICY IF EXISTS "Staff manage tenant orders" ON public.orders;

CREATE POLICY "Staff manage tenant orders" ON public.orders
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND restaurant_slug = public.auth_restaurant_slug()
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND restaurant_slug = public.auth_restaurant_slug()
    )
  );

-- 7. ORDER_ITEMS: Sadece ilgili restoranın yetkili kullanıcıları okuyabilir/yönetebilir
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read order_items" ON public.order_items;
DROP POLICY IF EXISTS "Public insert order_items" ON public.order_items;
DROP POLICY IF EXISTS "Public update order_items" ON public.order_items;
DROP POLICY IF EXISTS "Public delete order_items" ON public.order_items;
DROP POLICY IF EXISTS "Staff manage tenant order_items" ON public.order_items;

CREATE POLICY "Staff manage tenant order_items" ON public.order_items
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.id = order_id AND o.restaurant_slug = public.auth_restaurant_slug()
      )
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND EXISTS (
        SELECT 1 FROM public.orders o
        WHERE o.id = order_id AND o.restaurant_slug = public.auth_restaurant_slug()
      )
    )
  );

-- 8. CUSTOMERS: PII (telefon/adres) anonim erişime tamamen kapalı
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read customers" ON public.customers;
DROP POLICY IF EXISTS "Public insert customers" ON public.customers;
DROP POLICY IF EXISTS "Public update customers" ON public.customers;
DROP POLICY IF EXISTS "Public delete customers" ON public.customers;
DROP POLICY IF EXISTS "Staff manage tenant customers" ON public.customers;

CREATE POLICY "Staff manage tenant customers" ON public.customers
  FOR ALL
  TO authenticated
  USING (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND restaurant_slug = public.auth_restaurant_slug()
    )
  )
  WITH CHECK (
    public.is_super_admin()
    OR (
      public.auth_role() IN ('restaurant_admin', 'staff')
      AND restaurant_slug = public.auth_restaurant_slug()
    )
  );

-- 9. Geçmiş sıfırlama RPC'sini anonim kullanıcılara kapat
DO $$
BEGIN
  REVOKE EXECUTE ON FUNCTION public.reset_restaurant_history(TEXT) FROM anon;
  GRANT EXECUTE ON FUNCTION public.reset_restaurant_history(TEXT) TO authenticated;
EXCEPTION WHEN undefined_function THEN
  NULL;
END $$;
