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
      const url = `${SUPABASE_URL}/rest/v1/restaurants?select=id,name,slug,custom_domain,phone,address,instagram,primary_color,is_active,admin_email,admin_password&${filterQuery}&limit=1`;
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
        try {
          if (info.slug) localStorage.setItem("xubo_rest_info_" + info.slug, JSON.stringify(info));
        } catch (e) {}
      }
      return info;
    })();
    return readyPromise;
  };

  function renderBrandingFromInfo(info, slug) {
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

      const loginTitle = document.querySelector(".login-title");
      if (loginTitle && loginTitle.textContent.includes("Ginger")) {
        loginTitle.textContent = `${info.name} Yönetim`;
      }

      const adminBrandTitle = document.querySelector(".admin-brand-title");
      if (adminBrandTitle && adminBrandTitle.textContent.includes("Ginger")) {
        adminBrandTitle.textContent = info.name;
      }

      const footerBrandTitle = document.querySelector(".footer-brand-title");
      if (footerBrandTitle && footerBrandTitle.textContent.includes("Ginger")) {
        footerBrandTitle.textContent = info.name;
      }

      const loginEmailInput = document.getElementById("loginEmail");
      if (loginEmailInput && info.admin_email) {
        loginEmailInput.setAttribute("placeholder", info.admin_email);
      }

      const metaDesc = document.querySelector('meta[name="description"]');
      if (metaDesc) metaDesc.setAttribute("content", `${info.name} — Online Sipariş & Menü`);
      const ogTitle = document.querySelector('meta[property="og:title"]');
      if (ogTitle) ogTitle.setAttribute("content", `${info.name} — Online Sipariş & Menü`);
      const ogDesc = document.querySelector('meta[property="og:description"]');
      if (ogDesc) ogDesc.setAttribute("content", `${info.name} — Taze malzemeler ve hızlı online sipariş.`);
    }

    // Logo güncelleme (özellikle We Smash The Burger için özel logo)
    if (slug === "we-smash-the-burger") {
      const logoSrc = "images/we-smash-logo.jpg";
      document.querySelectorAll('link[rel="icon"], link[rel="apple-touch-icon"]').forEach(link => {
        link.setAttribute("href", logoSrc);
      });
      document.querySelectorAll('img[src*="images/logo.jpg"], .brand-logo img, .pin-gate-logo img').forEach(img => {
        img.setAttribute("src", logoSrc);
        img.setAttribute("alt", `${info.name || "We Smash The Burger"} Logo`);
        img.style.objectFit = "contain";
        img.style.background = "#ffffff";
      });

      // Vitrin sayfası Smash Burger teması (pizzaya dair metin bırakma)
      const heroTitle = document.querySelector(".hero-title");
      if (heroTitle) {
        heroTitle.innerHTML = `Gerçek smash,<br>sıcak ızgara,<br><span class="highlight">We Smash</span> lezzeti.`;
      }
      const heroDesc = document.querySelector(".hero-desc");
      if (heroDesc) {
        heroDesc.textContent = "Günlük taze dana kıyması, yüksek ısıda mühürlenmiş çıtır kenarlı smash köfteler ve özel soslar. Bahçelievler'in imza smash burger deneyimi.";
      }
      const heroBadges = document.querySelectorAll(".hero-badge-item");
      if (heroBadges.length >= 3) {
        heroBadges[0].querySelector(".hero-badge-title").textContent = "70 / 140 / 210 gr.";
        heroBadges[0].querySelector(".hero-badge-desc").textContent = "Single, Double ve Triple smash köfte gramaj seçenekleri.";
        heroBadges[1].querySelector(".hero-badge-title").textContent = "Sıcak Izgara";
        heroBadges[1].querySelector(".hero-badge-desc").textContent = "Yüksek ısıda ezilerek mühürlenen sulu ve çıtır kenarlı köfteler.";
        heroBadges[2].querySelector(".hero-badge-title").textContent = "%100 Dana";
        heroBadges[2].querySelector(".hero-badge-desc").textContent = "Katkısız taze dana köfte, erimiş cheddar ve günlük brioche ekmek.";
      }
      const featuredImg = document.querySelector(".featured-image-wrapper img");
      if (featuredImg) {
        featuredImg.setAttribute("src", "https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/76850501-950a-4301-bc42-c2ebca4ddaa0.jpg?width=600&height=600");
        featuredImg.setAttribute("alt", "We Smash The Burger — Houston Burger");
      }
      const featuredName = document.querySelector(".featured-name");
      if (featuredName) featuredName.textContent = "Houston Burger";
      const featuredDesc = document.querySelector(".featured-desc-mini");
      if (featuredDesc) featuredDesc.textContent = "2 adet 70 gr. smash köfte, 2x cheddar, ıceberg, turşu & burger sos";
      const featuredPill = document.querySelector(".featured-pill-price");
      if (featuredPill) featuredPill.textContent = "70 / 140 / 210 gr.";

      const craftTitle = document.querySelector("#hikaye .section-title");
      if (craftTitle) craftTitle.textContent = "İyi smash burger aceleye gelmez.";
      const craftDesc = document.querySelector("#hikaye .section-desc");
      if (craftDesc) craftDesc.textContent = "Bahçelievler Deli Hüseyin Paşa Caddesi'ndeki mutfağımızda her gün aynı tutkuyla hazırlanıyoruz. İyi bir smash burgerin sırrı; taze ette, doğru ısıda ve dengeli soslarda gizlidir.";
      const craftCards = document.querySelectorAll("#hikaye .craft-card");
      if (craftCards.length >= 3) {
        craftCards[0].querySelector(".craft-title").textContent = "Gramajına Göre Smash Köfte";
        craftCards[0].querySelector(".craft-text").textContent = "70 gr. tekli, 140 gr. double ve 210 gr. triple köfte gramajlarıyla damak tadınıza göre porsiyon seçin.";
        craftCards[1].querySelector(".craft-title").textContent = "Yüksek Isıda Izgara";
        craftCards[1].querySelector(".craft-text").textContent = "Özel smash presi ile ızgarada saniyeler içinde mühürlenen köfteler dışı çıtır, içi sulu kalır.";
        craftCards[2].querySelector(".craft-title").textContent = "Özel Soslar & Peynirler";
        craftCards[2].querySelector(".craft-text").textContent = "Cheddar, kaşar ve Erzincan tulum peynirleri; trüflü mayonez, barbekü, jalapeno salsa ve burger sosla buluşur.";
      }

      const menuDesc = document.querySelector("#menu .section-desc");
      if (menuDesc) menuDesc.textContent = "Her biri sipariş anında sıcak ızgarada hazırlanan smash burger menüler, burgerler ve eşlikçiler.";
      const menuSearch = document.getElementById("menuSearch");
      if (menuSearch) menuSearch.setAttribute("placeholder", "Burger, menü veya sos ara (örn: houston, texas...)");

      const sizeGuideTitle = document.querySelector(".size-guide-strip-title");
      if (sizeGuideTitle) {
        sizeGuideTitle.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> Gramaj Rehberi:`;
      }
      const sizeGuideItems = document.querySelector(".size-guide-items");
      if (sizeGuideItems) {
        sizeGuideItems.innerHTML = `
          <span><strong>Jr. (70 gr.):</strong> 1 Adet Smash Köfte</span>
          <span>•</span>
          <span><strong>Double (140 gr.):</strong> 2 Adet Smash Köfte</span>
          <span>•</span>
          <span><strong>Triple (210 gr.):</strong> 3 Adet Smash Köfte</span>
        `;
      }

      const hubBanner = document.querySelector(".web-order-hub-banner");
      if (hubBanner) {
        hubBanner.innerHTML = hubBanner.innerHTML
          .replace("En Hızlı & Doğrudan Fırından", "En Hızlı & Doğrudan Izgaradan")
          .replace(/Menüden pizzanızı ve boyutunuzu seçin[^<]*/g, "Menüden burgerinizi ve gramajınızı seçin, sepetinize ekleyin; mutfağımız anında hazırlasın ve canlı olarak takip edin.")
          .replace("🍕 Menüden Seç", "🍔 Menüden Seç");
      }

      const contactTitle = document.querySelector("#iletisim .section-title");
      if (contactTitle) contactTitle.textContent = "Bahçelievler'de Sıcak Bir Burger Molası";
      const contactDesc = document.querySelector("#iletisim .section-desc");
      if (contactDesc) contactDesc.textContent = "Bahçelievler'de ızgaradan yeni çıkmış smash burgerlerimizle sizleri ağırlamaktan mutluluk duyuyoruz.";

      const contactVals = document.querySelectorAll("#iletisim .contact-val");
      const fullAddress = info.address || "Deli Hüseyin Paşa Caddesi 36/B Ejder Apartmanı, Bahçelievler / İstanbul";
      if (contactVals[0]) contactVals[0].textContent = fullAddress;
      if (contactVals[2]) contactVals[2].innerHTML = "Haftanın her günü:<br>12:00 – 03:45 (Paket Servis &amp; Gel Al)";

      const mapLink = document.querySelector('#iletisim a[href*="maps.google.com"]');
      if (mapLink) {
        mapLink.setAttribute("href", `https://maps.google.com/?q=${encodeURIComponent(fullAddress)}`);
      }
      const mapIframe = document.querySelector(".map-frame-wrapper iframe");
      if (mapIframe) {
        mapIframe.setAttribute("title", `${info.name || "We Smash The Burger"} Konumu`);
        mapIframe.setAttribute("src", `https://maps.google.com/maps?q=${encodeURIComponent(fullAddress)}&t=&z=16&ie=UTF8&iwloc=&output=embed`);
      }

      const footerTagline = document.querySelector(".footer-tagline");
      if (footerTagline) footerTagline.textContent = "Bahçelievler'in imza smash burger noktası. Taze dana eti, sıcak ızgara ve özel soslar.";

      const footerLinks = document.querySelectorAll(".footer-links li");
      footerLinks.forEach(li => {
        if (li.textContent.includes("Rıdvanpaşa")) li.textContent = fullAddress;
        if (li.textContent.includes("Kadıköy / İstanbul")) li.textContent = "Bahçelievler / İstanbul";
        if (li.textContent.includes("gingerpizza") && !info.instagram) li.style.display = "none";
      });
      if (!info.instagram) {
        document.querySelectorAll("#iletisim .contact-item").forEach(item => {
          if (item.textContent.includes("Instagram")) item.style.display = "none";
        });
        document.querySelectorAll('.cta-row a[href*="instagram"]').forEach(a => {
          a.style.display = "none";
        });
      }
      const footerBottomMeta = document.querySelector(".footer-bottom span");
      if (footerBottomMeta && footerBottomMeta.textContent.includes("Pizza")) {
        footerBottomMeta.textContent = "Bahçelievler, İstanbul · Smash Burger";
      }

      // Admin Paneli — Pizza yerine Burger / Gramaj metinleri
      const tabBtnMenu = document.getElementById("tabBtnMenu");
      if (tabBtnMenu) tabBtnMenu.textContent = "🍔 Menü & Dükkan Yönetimi";
      const statPizzasEl = document.getElementById("statPizzas");
      if (statPizzasEl && statPizzasEl.parentElement) {
        const lbl = statPizzasEl.parentElement.querySelector(".stat-label");
        const sub = statPizzasEl.parentElement.querySelector(".stat-sub");
        if (lbl) lbl.textContent = "Gramajlı Ürün";
        if (sub) sub.textContent = "Çoklu gramaj seçenekleri";
      }
      const adminStoreMsg = document.getElementById("adminStoreMessage");
      if (adminStoreMsg) {
        adminStoreMsg.setAttribute("placeholder", "Örn: Mutfak yoğunluğu nedeniyle 30 dk siparişe ara verdik.");
      }
      const reportSubBtn = document.querySelector('[data-report-tab="products"]');
      if (reportSubBtn) reportSubBtn.textContent = "🍔 Ürün Raporu";
      document.querySelectorAll("#itemModal label, #itemModal option, #itemModal .form-label").forEach(el => {
        if (el.textContent.includes("Pizza")) el.textContent = el.textContent.replace(/Pizza/g, "Burger / Gramajlı");
        if (el.textContent.includes("Small (24-26 cm)")) el.textContent = "70 gr. (Single)";
        if (el.textContent.includes("Medium (30-32 cm)")) el.textContent = "140 gr. (Double)";
        if (el.textContent.includes("Mega / XL (40-42 cm)")) el.textContent = "210 gr. (Triple)";
      });

      // KDS (orders.html) — Pizza / Fırın yerine Izgara / Mutfak
      const prepTitle = document.querySelector(".col-prep .col-title-wrap span");
      if (prepTitle) prepTitle.textContent = "🍔 Izgarada / Hazırlanıyor";
      const prepEmpty = document.querySelector("#listPrep .col-empty");
      if (prepEmpty) prepEmpty.textContent = "Hazırlanan sipariş yok.";
      const kdsMsgInput = document.getElementById("kdsStoreMessageInput");
      if (kdsMsgInput) kdsMsgInput.setAttribute("placeholder", "Örn: Mutfak yoğunluğu nedeniyle kısa bir ara verdik.");

      // Hazırlanıyoruz Açılış Sayfası (index.html)
      const heroEyebrow = document.querySelector(".hero-eyebrow");
      if (heroEyebrow && heroEyebrow.textContent.includes("Fırın")) {
        heroEyebrow.textContent = "🔥 Izgaramız Sıcak, Sitemiz Hazırlanıyor";
      }
      const comingTitle = document.getElementById("comingTitle");
      if (comingTitle) {
        comingTitle.innerHTML = "Yeni smash burger menümüz ve online sipariş sistemimiz <em>çok yakında</em> burada.";
      }
      const comingDesc = document.querySelector(".coming-card .hero-desc");
      if (comingDesc && comingDesc.textContent.includes("taş fırın")) {
        comingDesc.textContent = "Bahçelievler'deki mutfağımızdan sıcacık smash burgerlerimizi doğrudan web sitemiz üzerinden sipariş edebilmeniz için son hazırlıklarımızı yapıyoruz. Bu sırada telefonla hemen sipariş verebilirsiniz.";
      }
      const comingInfoVals = document.querySelectorAll(".info-box .info-val");
      if (comingInfoVals.length >= 4) {
        if (comingInfoVals[0]) comingInfoVals[0].innerHTML = `${fullAddress}<span class="info-sub"><a href="https://maps.google.com/?q=${encodeURIComponent(fullAddress)}" target="_blank" rel="noopener noreferrer">Google Haritalar'da Aç →</a></span>`;
        if (comingInfoVals[2]) comingInfoVals[2].innerHTML = `Haftanın her günü: 12:00 – 03:45<span class="info-sub">Paket Servis &amp; Gel Al</span>`;
        if (comingInfoVals[3] && !info.instagram) comingInfoVals[3].closest(".info-item").style.display = "none";
      }
      const comingFooterMeta = document.querySelector(".site-footer div");
      if (comingFooterMeta && comingFooterMeta.textContent.includes("Ginger")) {
        comingFooterMeta.textContent = `© 2026 ${info.name || "We Smash The Burger"} · Bahçelievler, İstanbul`;
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
  }

  window.applyDynamicBranding = async function () {
    const slug = window.getActiveRestaurantSlug();
    try {
      // Önbellek varsa ağ yanıtı beklemeden anında uygula (FOUC önleme)
      if (slug && slug !== "ginger-pizza") {
        try {
          const cachedRaw = localStorage.getItem("xubo_rest_info_" + slug);
          if (cachedRaw) {
            const cachedInfo = JSON.parse(cachedRaw);
            if (cachedInfo && cachedInfo.slug === slug) {
              window.__ACTIVE_RESTAURANT_INFO__ = cachedInfo;
              renderBrandingFromInfo(cachedInfo, slug);
              document.documentElement.style.visibility = "";
            }
          }
        } catch (e) {}
      }
      const info = await window.ensureRestaurantConfigReady();
      renderBrandingFromInfo(info, window.getActiveRestaurantSlug());
    } finally {
      document.documentElement.style.visibility = "";
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
