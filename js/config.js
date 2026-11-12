// Ginger Pizza & Multi-Tenant Platform Supabase Bağlantı Konfigürasyonu
(function () {
  const SUPABASE_URL = "https://nidhfqjotaurxlqpfwqp.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZGhmcWpvdGF1cnhscXBmd3FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzOTUzOTYsImV4cCI6MjEwOTk3MTM5Nn0.NbZ7MotgVuisLUBwuUe0BAdvIBCLUFjWupvqmbYkZUM";

  const KNOWN_PLATFORM_HOSTS = new Set([
    "localhost",
    "127.0.0.1",
    "xubo.app",
    "www.xubo.app",
    "gingerpizza.com",
    "www.gingerpizza.com"
  ]);

  function isCustomDomainHost(hostname) {
    if (!hostname) return false;
    const h = String(hostname).toLowerCase();
    if (KNOWN_PLATFORM_HOSTS.has(h)) return false;
    if (h.endsWith(".github.io") || h.endsWith(".pages.dev") || h.endsWith(".vercel.app")) return false;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(h)) return false;
    // Subdomain of xubo.app (e.g. moda-burger.xubo.app) is handled as subdomain, not custom_domain
    if (h.endsWith(".xubo.app")) return false;
    return true;
  }

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

        const hostname = String(window.location.hostname || "").toLowerCase();

        // 2. Özel Domain önbelleği (örn: www.modaburger.com -> moda-burger)
        if (isCustomDomainHost(hostname)) {
          try {
            const cachedSlug = localStorage.getItem("xubo_domain_slug_" + hostname);
            if (cachedSlug && cachedSlug.trim()) return cachedSlug.trim().toLowerCase();
          } catch (e) {}
        }

        // 3. Subdomain tespiti: örn. restoran-2.xubo.app
        const parts = hostname.split(".");
        if (parts.length >= 3 && !hostname.endsWith(".github.io") && !/^\d+\.\d+\.\d+\.\d+$/.test(hostname)) {
          const sub = parts[0];
          const reserved = ["www", "api", "admin", "panel", "yonetim", "master", "mail", "app", "siparis"];
          if (sub && !reserved.includes(sub)) {
            return sub;
          }
        }

        // 4. Daha önce aynı oturumda seçilmiş slug varsa hatırla
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
    url: SUPABASE_URL,
    anonKey: SUPABASE_ANON_KEY
  };

  window.getActiveRestaurantSlug = function () {
    return (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.restaurantSlug) || "ginger-pizza";
  };

  async function fetchRestaurantByQuery(filterQuery) {
    if (typeof fetch !== "function") return null;
    try {
      const url = `${SUPABASE_URL}/rest/v1/restaurants?select=id,name,slug,custom_domain,phone,address,instagram,primary_color,is_active&${filterQuery}&limit=1`;
      const res = await fetch(url, {
        headers: {
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`
        }
      });
      if (!res.ok) return null;
      const rows = await res.json();
      return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
    } catch (e) {
      return null;
    }
  }

  let readyPromise = null;
  window.ensureRestaurantConfigReady = function () {
    if (readyPromise) return readyPromise;
    readyPromise = (async () => {
      const hostname = (typeof window !== "undefined" && window.location)
        ? String(window.location.hostname || "").toLowerCase()
        : "";
      const params = (typeof window !== "undefined" && window.location)
        ? new URLSearchParams(window.location.search)
        : null;
      const hasQuery = !!(params && (params.get("r") || params.get("restaurant")));

      let info = null;
      if (!hasQuery && isCustomDomainHost(hostname)) {
        const bareHost = hostname.replace(/^www\./, "");
        const withWww = hostname.startsWith("www.") ? hostname : `www.${hostname}`;
        info = await fetchRestaurantByQuery(
          `or=(custom_domain.ilike.${encodeURIComponent(hostname)},custom_domain.ilike.${encodeURIComponent(bareHost)},custom_domain.ilike.${encodeURIComponent(withWww)})`
        );
        if (info && info.slug) {
          window.SUPABASE_CONFIG.restaurantSlug = info.slug;
          try {
            localStorage.setItem("xubo_domain_slug_" + hostname, info.slug);
          } catch (e) {}
        }
      }

      const currentSlug = window.getActiveRestaurantSlug();
      if (!info && currentSlug && currentSlug !== "ginger-pizza") {
        info = await fetchRestaurantByQuery(`slug=eq.${encodeURIComponent(currentSlug)}`);
      }
      if (info) {
        window.__ACTIVE_RESTAURANT_INFO__ = info;
      }
      return info;
    })();
    return readyPromise;
  };

  window.applyDynamicBranding = async function () {
    const info = await window.ensureRestaurantConfigReady();
    const slug = window.getActiveRestaurantSlug();
    if (!info || slug === "ginger-pizza") return;

    if (info.primary_color) {
      document.documentElement.style.setProperty("--ginger-500", info.primary_color);
      document.documentElement.style.setProperty("--ginger-600", info.primary_color);
    }

    if (info.name) {
      const pageTitle = document.title || "";
      if (pageTitle.includes("Admin") || pageTitle.includes("Yönetim")) {
        document.title = `${info.name} — Restoran Yönetim Paneli`;
      } else if (pageTitle.includes("KDS") || pageTitle.includes("Mutfak")) {
        document.title = `${info.name} — Canlı Sipariş & Mutfak Ekranı (KDS)`;
      } else {
        document.title = `${info.name} — Online Sipariş & Menü`;
      }

      const brandTitle = document.querySelector(".brand-title");
      if (brandTitle) brandTitle.textContent = info.name;

      const pinTitle = document.getElementById("pinGateTitle");
      if (pinTitle) pinTitle.textContent = info.name;

      const secTitle = document.querySelector("#menu .section-title");
      if (secTitle) secTitle.textContent = `${info.name} Menüsü`;

      const footerCopy = document.querySelector(".footer-bottom div, .site-footer div");
      if (footerCopy && footerCopy.textContent.includes("Ginger Pizza")) {
        footerCopy.textContent = `© 2026 ${info.name}. Tüm hakları saklıdır.`;
      }
    }

    if (info.phone) {
      const cleanTel = info.phone.replace(/\s+/g, "");
      document.querySelectorAll('a[href^="tel:"]').forEach(a => {
        a.setAttribute("href", `tel:${cleanTel}`);
        const textNode = Array.from(a.childNodes).find(n => n.nodeType === 3 && n.textContent.trim());
        if (textNode) {
          textNode.textContent = " " + info.phone;
        } else if (!a.querySelector("svg")) {
          a.textContent = info.phone;
        }
      });
      document.querySelectorAll(".btn-hub-action").forEach(el => {
        if (/0216/.test(el.textContent)) el.textContent = info.phone;
      });
    }

    if (info.is_active === false && typeof document !== "undefined") {
      const isStorefront = !!document.getElementById("menu") && !document.getElementById("adminMenuSection");
      if (isStorefront && !document.getElementById("inactiveStoreBanner")) {
        const banner = document.createElement("div");
        banner.id = "inactiveStoreBanner";
        banner.style.cssText = "position:fixed;inset:0;z-index:9999;background:rgba(15,23,42,0.92);color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px;";
        banner.innerHTML = `<h2 style="font-size:1.5rem;margin-bottom:8px;">${info.name || "Bu Mağaza"}</h2><p style="color:#cbd5e1;max-width:420px;">Bu restoran şu anda geçici olarak hizmet dışıdır.</p>`;
        document.body.appendChild(banner);
      }
    }
  };

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => { window.applyDynamicBranding(); });
    } else {
      window.applyDynamicBranding();
    }
  }
})();
