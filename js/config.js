// Ginger Pizza & Multi-Tenant Platform Supabase Bağlantı Konfigürasyonu
(function () {
  function resolveActiveRestaurantSlug() {
    try {
      if (typeof window !== "undefined" && window.location) {
        // 1. URL Query Param: ?r=slug veya ?restaurant=slug
        const params = new URLSearchParams(window.location.search);
        const querySlug = params.get("r") || params.get("restaurant");
        if (querySlug && querySlug.trim()) {
          const clean = querySlug.trim().toLowerCase();
          try {
            sessionStorage.setItem("ginger_active_restaurant_slug", clean);
          } catch (e) {}
          return clean;
        }

        // 2. Subdomain tespiti: örn. restoran-2.xubo.app veya restoran-2.localhost
        const hostname = String(window.location.hostname || "").toLowerCase();
        const parts = hostname.split(".");
        // localhost haricinde en az 3 parça olmalı (subdomain.domain.tld)
        // örn: ["restoran-2", "xubo", "app"] -> sub: "restoran-2"
        if (parts.length >= 3 && !hostname.endsWith(".github.io")) {
          const sub = parts[0];
          const reserved = ["www", "api", "admin", "panel", "yonetim", "master", "mail", "app"];
          if (sub && !reserved.includes(sub)) {
            return sub;
          }
        }

        // 3. Daha önce aynı oturumda seçilmiş slug varsa hatırla
        try {
          const stored = sessionStorage.getItem("ginger_active_restaurant_slug");
          if (stored && stored.trim()) return stored.trim().toLowerCase();
        } catch (e) {}
      }
    } catch (err) {
      console.warn("Slug resolution fallback:", err);
    }
    return "ginger-pizza";
  }

  const activeSlug = resolveActiveRestaurantSlug();

  window.SUPABASE_CONFIG = {
    restaurantSlug: activeSlug,
    url: "https://nidhfqjotaurxlqpfwqp.supabase.co",
    anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZGhmcWpvdGF1cnhscXBmd3FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzOTUzOTYsImV4cCI6MjEwOTk3MTM5Nn0.NbZ7MotgVuisLUBwuUe0BAdvIBCLUFjWupvqmbYkZUM"
  };

  // Global yardımcı fonksiyon (tüm scriptler tarafından doğrudan çağrılabilir)
  window.getActiveRestaurantSlug = function () {
    return (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.restaurantSlug) || "ginger-pizza";
  };
})();

