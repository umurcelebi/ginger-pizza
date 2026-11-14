// Ginger Pizza & Multi-Tenant Platform Supabase Bağlantı Konfigürasyonu
(function () {

  // Görsel değişiminde eski (Ginger) görselin yeni görsel yüklenene kadar ekranda kalmasını engeller
  function swapImg(img, src) {
    if (!img || img.getAttribute("src") === src) return;
    img.style.visibility = "hidden";
    img.removeAttribute("srcset");
    const show = () => { img.style.visibility = ""; };
    img.addEventListener("load", show, { once: true });
    img.addEventListener("error", show, { once: true });
    img.setAttribute("src", src);
    if (img.complete && img.naturalWidth > 0) show();
  }
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
      const baseCols = "id,name,slug,custom_domain,phone,address,instagram,primary_color,is_active";
      const colsWithProfile = baseCols + ",profile";
      const headers = {
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`
      };
      let res = await fetch(`${SUPABASE_URL}/rest/v1/restaurants?select=${colsWithProfile}&${filterQuery}&limit=1`, { headers });
      if (res.status === 400) {
        res = await fetch(`${SUPABASE_URL}/rest/v1/restaurants?select=${baseCols}&${filterQuery}&limit=1`, { headers });
      }
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
          if (info.slug) {
            const { admin_password: _ignored, ...safeCacheInfo } = info;
            localStorage.setItem("xubo_rest_info_" + info.slug, JSON.stringify(safeCacheInfo));
          }
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

    // Tüm non-ginger restoranlar için tam veri odaklı profil + sızıntısız genel varsayılanlar
    const rawProfile = (info.profile && typeof info.profile === "object") ? info.profile : {};
    const wsFallback = slug === "we-smash-the-burger" ? {
      logo_url: "images/we-smash-logo.jpg",
      hero_tag: "Bahçelievler'in İmza Smash Burgeri",
      hero_title_html: `Gerçek smash,<br>sıcak ızgara,<br><span class="highlight">We Smash</span> lezzeti.`,
      hero_desc: "Günlük taze dana kıyması, yüksek ısıda mühürlenmiş çıtır kenarlı smash köfteler ve özel soslar. Bahçelievler'in imza smash burger deneyimi.",
      featured: {
        image: "https://yemeksepeti.dhmedia.io/image/global-menu-service/YS_TR/vendor/rcqj/product/76850501-950a-4301-bc42-c2ebca4ddaa0.jpg?width=600&height=600",
        name: "Houston Burger",
        desc: "2 adet 70 gr. smash köfte, 2x cheddar, ıceberg, turşu & burger sos",
        pill: "70 / 140 / 210 gr."
      },
      story_title: "İyi smash burger aceleye gelmez.",
      story_desc: "Bahçelievler Deli Hüseyin Paşa Caddesi'ndeki mutfağımızda her gün aynı tutkuyla hazırlanıyoruz. İyi bir smash burgerin sırrı; taze ette, doğru ısıda ve dengeli soslarda gizlidir.",
      craft_cards: [
        { title: "Gramajına Göre Smash Köfte", text: "70 gr. tekli, 140 gr. double ve 210 gr. triple köfte gramajlarıyla damak tadınıza göre porsiyon seçin." },
        { title: "Yüksek Isıda Izgara", text: "Özel smash presi ile ızgarada saniyeler içinde mühürlenen köfteler dışı çıtır, içi sulu kalır." },
        { title: "Özel Soslar & Peynirler", text: "Cheddar, kaşar ve Erzincan tulum peynirleri; trüflü mayonez, barbekü, jalapeno salsa ve burger sosla buluşur." }
      ],
      menu_desc: "Her biri sipariş anında sıcak ızgarada hazırlanan smash burger menüler, burgerler ve eşlikçiler.",
      search_placeholder: "Burger, menü veya sos ara (örn: houston, texas...)",
      size_guide_title: "Gramaj Rehberi:",
      size_guide_items_html: `<span><strong>Jr. (70 gr.):</strong> 1 Adet Smash Köfte</span><span>•</span><span><strong>Double (140 gr.):</strong> 2 Adet Smash Köfte</span><span>•</span><span><strong>Triple (210 gr.):</strong> 3 Adet Smash Köfte</span>`,
      hub_banner_eyebrow: "En Hızlı & Doğrudan Izgaradan",
      hub_banner_desc: "Menüden burgerinizi ve gramajınızı seçin, sepetinize ekleyin; mutfağımız anında hazırlasın ve canlı olarak takip edin.",
      hub_cta_label: "🍔 Menüden Seç",
      contact_title: "Bahçelievler'de Sıcak Bir Burger Molası",
      contact_desc: "Bahçelievler'de ızgaradan yeni çıkmış smash burgerlerimizle sizleri ağırlamaktan mutluluk duyuyoruz.",
      hours_html: "Haftanın her günü:<br>12:00 – 03:45 (Paket Servis &amp; Gel Al)",
      footer_tagline: "Bahçelievler'in imza smash burger noktası. Taze dana eti, sıcak ızgara ve özel soslar.",
      footer_city: "Bahçelievler / İstanbul",
      footer_meta: "Bahçelievler, İstanbul · Smash Burger",
      coming_eyebrow: "🔥 Izgaramız Sıcak, Sitemiz Hazırlanıyor",
      coming_title_html: "Yeni smash burger menümüz ve online sipariş sistemimiz <em>çok yakında</em> burada.",
      coming_desc: "Bahçelievler'deki mutfağımızdan sıcacık smash burgerlerimizi doğrudan web sitemiz üzerinden sipariş edebilmeniz için son hazırlıklarımızı yapıyoruz. Bu sırada telefonla hemen sipariş verebilirsiniz.",
      coming_hours_html: `Haftanın her günü: 12:00 – 03:45<span class="info-sub">Paket Servis &amp; Gel Al</span>`
    } : {};

    const p = Object.assign({}, wsFallback, rawProfile);
    const brandName = info.name || "Restoran";
    const fullAddress = (info.address || "").trim();

    // Logo
    if (p.logo_url) {
      document.querySelectorAll('link[rel="icon"], link[rel="apple-touch-icon"]').forEach(link => {
        link.setAttribute("href", p.logo_url);
      });
      document.querySelectorAll('img[src*="images/logo.jpg"], .brand-logo img, .pin-gate-logo img').forEach(img => {
        swapImg(img, p.logo_url);
        img.setAttribute("alt", `${brandName} Logo`);
        img.style.objectFit = "contain";
        img.style.background = "#ffffff";
        img.style.display = "";
      });
    } else {
      document.querySelectorAll('img[src*="images/logo.jpg"], .brand-logo img, .pin-gate-logo img').forEach(img => {
        img.style.display = "none";
      });
    }

    // Hero
    const heroTag = document.querySelector(".hero-tag");
    if (heroTag) {
      const dot = heroTag.querySelector(".hero-tag-dot");
      const tagText = p.hero_tag || brandName;
      if (dot) {
        heroTag.innerHTML = "";
        heroTag.appendChild(dot);
        heroTag.appendChild(document.createTextNode(" " + tagText));
      } else {
        heroTag.textContent = tagText;
      }
    }
    const heroTitle = document.querySelector(".hero-title");
    if (heroTitle) {
      heroTitle.innerHTML = p.hero_title_html || `Taze lezzet,<br>özenli mutfak,<br><span class="highlight">${brandName}</span>.`;
    }
    const heroDesc = document.querySelector(".hero-desc");
    if (heroDesc) {
      heroDesc.textContent = p.hero_desc || `${brandName} mutfağından özenle hazırlanan taze lezzetleri doğrudan online sipariş edin.`;
    }
    const heroBadges = document.querySelectorAll(".hero-badge-item");
    if (heroBadges.length >= 3) {
      if (Array.isArray(p.hero_badges) && p.hero_badges.length >= 3) {
        p.hero_badges.slice(0, 3).forEach((b, idx) => {
          const t = heroBadges[idx].querySelector(".hero-badge-title");
          const d = heroBadges[idx].querySelector(".hero-badge-desc");
          if (t) t.textContent = b.title || "";
          if (d) d.textContent = b.desc || "";
        });
      } else if (slug === "we-smash-the-burger") {
        heroBadges[0].querySelector(".hero-badge-title").textContent = "70 / 140 / 210 gr.";
        heroBadges[0].querySelector(".hero-badge-desc").textContent = "Single, Double ve Triple smash köfte gramaj seçenekleri.";
        heroBadges[1].querySelector(".hero-badge-title").textContent = "Sıcak Izgara";
        heroBadges[1].querySelector(".hero-badge-desc").textContent = "Yüksek ısıda ezilerek mühürlenen sulu ve çıtır kenarlı köfteler.";
        heroBadges[2].querySelector(".hero-badge-title").textContent = "%100 Dana";
        heroBadges[2].querySelector(".hero-badge-desc").textContent = "Katkısız taze dana köfte, erimiş cheddar ve günlük brioche ekmek.";
      } else {
        const badgesWrap = heroBadges[0].closest(".hero-badges");
        if (badgesWrap) badgesWrap.style.display = "none";
      }
    }

    // Öne çıkan vitrin kartı
    const heroVisual = document.querySelector(".hero-visual");
    if (p.featured && p.featured.image) {
      if (heroVisual) heroVisual.style.display = "";
      const featuredImg = document.querySelector(".featured-image-wrapper img");
      if (featuredImg) {
        swapImg(featuredImg, p.featured.image);
        featuredImg.setAttribute("alt", `${brandName} — ${p.featured.name || "Öne Çıkan"}`);
      }
      const featuredName = document.querySelector(".featured-name");
      if (featuredName) featuredName.textContent = p.featured.name || "";
      const featuredDesc = document.querySelector(".featured-desc-mini");
      if (featuredDesc) featuredDesc.textContent = p.featured.desc || "";
      const featuredPill = document.querySelector(".featured-pill-price");
      if (featuredPill) featuredPill.textContent = p.featured.pill || "";
    } else if (heroVisual) {
      heroVisual.style.display = "none";
    }

    // Hikaye bölümü (#hikaye)
    const craftTitle = document.querySelector("#hikaye .section-title");
    if (craftTitle) craftTitle.textContent = p.story_title || `${brandName} Mutfağı`;
    const craftDesc = document.querySelector("#hikaye .section-desc");
    if (craftDesc) {
      craftDesc.textContent = p.story_desc || (fullAddress
        ? `${fullAddress} adresindeki mutfağımızda her gün aynı özenle hazırlanıyoruz.`
        : `${brandName} mutfağında her gün aynı özen ve tutkuyla hazırlanıyoruz.`);
    }
    const craftGrid = document.querySelector("#hikaye .craft-grid");
    const craftCards = document.querySelectorAll("#hikaye .craft-card");
    if (Array.isArray(p.craft_cards) && p.craft_cards.length > 0 && craftCards.length > 0) {
      if (craftGrid) craftGrid.style.display = "";
      craftCards.forEach((card, idx) => {
        const item = p.craft_cards[idx];
        if (!item) {
          card.style.display = "none";
          return;
        }
        card.style.display = "";
        const t = card.querySelector(".craft-title");
        const d = card.querySelector(".craft-text");
        if (t) t.textContent = item.title || "";
        if (d) d.textContent = item.text || "";
      });
    } else if (craftGrid) {
      craftGrid.style.display = "none";
    }

    // Menü bölümü (#menu)
    const menuDesc = document.querySelector("#menu .section-desc");
    if (menuDesc) menuDesc.textContent = p.menu_desc || `${brandName} mutfağından sipariş anında taze hazırlanan lezzetler.`;
    const menuSearch = document.getElementById("menuSearch");
    if (menuSearch) menuSearch.setAttribute("placeholder", p.search_placeholder || "Menüde ürün veya kategori ara...");

    const sizeGuideStrip = document.querySelector(".size-guide-strip");
    const sizeGuideTitle = document.querySelector(".size-guide-strip-title");
    const sizeGuideItems = document.querySelector(".size-guide-items");
    const sgTitle = p.size_guide_title || (slug === "we-smash-the-burger" ? "Gramaj Rehberi:" : "");
    const sgItems = p.size_guide_items_html || (slug === "we-smash-the-burger"
      ? `<span><strong>Jr. (70 gr.):</strong> 1 Adet Smash Köfte</span><span>•</span><span><strong>Double (140 gr.):</strong> 2 Adet Smash Köfte</span><span>•</span><span><strong>Triple (210 gr.):</strong> 3 Adet Smash Köfte</span>`
      : "");
    if (sgTitle || sgItems) {
      if (sizeGuideStrip) sizeGuideStrip.style.display = "";
      if (sizeGuideTitle && sgTitle) {
        sizeGuideTitle.innerHTML = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg> ${sgTitle}`;
      }
      if (sizeGuideItems && sgItems) sizeGuideItems.innerHTML = sgItems;
    } else if (sizeGuideStrip) {
      sizeGuideStrip.style.display = "none";
    }

    const hubBanner = document.querySelector(".web-order-hub-banner");
    if (hubBanner) {
      hubBanner.innerHTML = hubBanner.innerHTML
        .replace("En Hızlı & Doğrudan Fırından", p.hub_banner_eyebrow || "En Hızlı & Doğrudan Mutfaktan")
        .replace(/Menüden pizzanızı ve boyutunuzu seçin[^<]*/g, p.hub_banner_desc || "Menüden ürününüzü seçin, sepetinize ekleyin; mutfağımız anında hazırlasın ve canlı olarak takip edin.")
        .replace("🍕 Menüden Seç", p.hub_cta_label || "🍽️ Menüden Seç");
    }

    // İletişim & Harita (#iletisim)
    const contactTitle = document.querySelector("#iletisim .section-title");
    if (contactTitle) contactTitle.textContent = p.contact_title || `${brandName} ile İletişim`;
    const contactDesc = document.querySelector("#iletisim .section-desc");
    if (contactDesc) contactDesc.textContent = p.contact_desc || "Sipariş ve sorularınız için bize dilediğiniz zaman ulaşabilirsiniz.";

    const contactVals = document.querySelectorAll("#iletisim .contact-val");
    if (contactVals[0]) {
      contactVals[0].textContent = fullAddress || "Adres bilgisi yakında eklenecektir.";
    }
    if (contactVals[2]) {
      if (p.hours_html) {
        contactVals[2].innerHTML = p.hours_html;
      } else {
        const hoursItem = contactVals[2].closest(".contact-item");
        if (hoursItem) hoursItem.style.display = "none";
      }
    }

    const mapLink = document.querySelector('#iletisim a[href*="maps.google.com"]');
    const mapWrapper = document.querySelector(".map-frame-wrapper");
    const mapIframe = document.querySelector(".map-frame-wrapper iframe");
    if (fullAddress) {
      if (mapLink) mapLink.setAttribute("href", `https://maps.google.com/?q=${encodeURIComponent(fullAddress)}`);
      if (mapWrapper) mapWrapper.style.display = "";
      if (mapIframe) {
        mapIframe.setAttribute("title", `${brandName} Konumu`);
        mapIframe.setAttribute("src", `https://maps.google.com/maps?q=${encodeURIComponent(fullAddress)}&t=&z=16&ie=UTF8&iwloc=&output=embed`);
      }
    } else {
      if (mapLink) mapLink.style.display = "none";
      if (mapWrapper) mapWrapper.style.display = "none";
    }

    // Instagram & Footer
    const footerTagline = document.querySelector(".footer-tagline");
    if (footerTagline) footerTagline.textContent = p.footer_tagline || `${brandName} — Özenle hazırlanan taze lezzetler.`;

    const footerLinks = document.querySelectorAll(".footer-links li");
    footerLinks.forEach(li => {
      if (li.textContent.includes("Rıdvanpaşa")) {
        if (fullAddress) li.textContent = fullAddress;
        else li.style.display = "none";
      }
      if (li.textContent.includes("Kadıköy / İstanbul")) {
        if (p.footer_city) li.textContent = p.footer_city;
        else li.style.display = "none";
      }
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
      footerBottomMeta.textContent = p.footer_meta || brandName;
    }

    // Admin Paneli — Pizza yerine restoran profiline / genel mutfağa uygun etiketler
    const tabBtnMenu = document.getElementById("tabBtnMenu");
    if (tabBtnMenu) tabBtnMenu.textContent = slug === "we-smash-the-burger" ? "🍔 Menü & Dükkan Yönetimi" : "🍽️ Menü & Dükkan Yönetimi";
    const statPizzasEl = document.getElementById("statPizzas");
    if (statPizzasEl && statPizzasEl.parentElement) {
      const lbl = statPizzasEl.parentElement.querySelector(".stat-label");
      const sub = statPizzasEl.parentElement.querySelector(".stat-sub");
      if (lbl) lbl.textContent = slug === "we-smash-the-burger" ? "Gramajlı Ürün" : "Varyantlı Ürün";
      if (sub) sub.textContent = slug === "we-smash-the-burger" ? "Çoklu gramaj seçenekleri" : "Çoklu boyut / seçenek";
    }
    const adminStoreMsg = document.getElementById("adminStoreMessage");
    if (adminStoreMsg) {
      adminStoreMsg.setAttribute("placeholder", "Örn: Mutfak yoğunluğu nedeniyle 30 dk siparişe ara verdik.");
    }
    const reportSubBtn = document.querySelector('[data-report-tab="products"]');
    if (reportSubBtn) reportSubBtn.textContent = slug === "we-smash-the-burger" ? "🍔 Ürün Raporu" : "📊 Ürün Raporu";
    document.querySelectorAll("#itemModal label, #itemModal option, #itemModal .form-label").forEach(el => {
      if (el.textContent.includes("Pizza")) {
        el.textContent = el.textContent.replace(/Pizza/g, slug === "we-smash-the-burger" ? "Burger / Gramajlı" : "Çoklu Seçenekli");
      }
      if (slug === "we-smash-the-burger") {
        if (el.textContent.includes("Small (24-26 cm)")) el.textContent = "70 gr. (Single)";
        if (el.textContent.includes("Medium (30-32 cm)")) el.textContent = "140 gr. (Double)";
        if (el.textContent.includes("Mega / XL (40-42 cm)")) el.textContent = "210 gr. (Triple)";
      } else {
        if (el.textContent.includes("Small (24-26 cm)")) el.textContent = "Küçük / Seçenek 1";
        if (el.textContent.includes("Medium (30-32 cm)")) el.textContent = "Orta / Seçenek 2";
        if (el.textContent.includes("Mega / XL (40-42 cm)")) el.textContent = "Büyük / Seçenek 3";
      }
    });

    // KDS (orders.html) — Pizza / Fırın yerine Mutfak
    const prepTitle = document.querySelector(".col-prep .col-title-wrap span");
    if (prepTitle) prepTitle.textContent = slug === "we-smash-the-burger" ? "🍔 Izgarada / Hazırlanıyor" : "👨‍🍳 Mutfakta / Hazırlanıyor";
    const prepEmpty = document.querySelector("#listPrep .col-empty");
    if (prepEmpty) prepEmpty.textContent = "Hazırlanan sipariş yok.";
    const kdsMsgInput = document.getElementById("kdsStoreMessageInput");
    if (kdsMsgInput) kdsMsgInput.setAttribute("placeholder", "Örn: Mutfak yoğunluğu nedeniyle kısa bir ara verdik.");

    // Hazırlanıyoruz Açılış Sayfası (index.html)
    const heroEyebrow = document.querySelector(".hero-eyebrow");
    if (heroEyebrow && heroEyebrow.textContent.includes("Fırın")) {
      heroEyebrow.textContent = p.coming_eyebrow || "✨ Mutfağımız Hazırlanıyor";
    }
    const comingTitle = document.getElementById("comingTitle");
    if (comingTitle) {
      comingTitle.innerHTML = p.coming_title_html || `${brandName} menümüz ve online sipariş sistemimiz <em>çok yakında</em> burada.`;
    }
    const comingDesc = document.querySelector(".coming-card .hero-desc");
    if (comingDesc && comingDesc.textContent.includes("taş fırın")) {
      comingDesc.textContent = p.coming_desc || `${brandName} lezzetlerini doğrudan web sitemiz üzerinden sipariş edebilmeniz için son hazırlıklarımızı yapıyoruz.`;
    }
    const comingInfoVals = document.querySelectorAll(".info-box .info-val");
    if (comingInfoVals.length >= 4) {
      if (comingInfoVals[0]) {
        if (fullAddress) {
          comingInfoVals[0].innerHTML = `${fullAddress}<span class="info-sub"><a href="https://maps.google.com/?q=${encodeURIComponent(fullAddress)}" target="_blank" rel="noopener noreferrer">Google Haritalar'da Aç →</a></span>`;
        } else {
          const item = comingInfoVals[0].closest(".info-item");
          if (item) item.style.display = "none";
        }
      }
      if (comingInfoVals[2]) {
        if (p.coming_hours_html) {
          comingInfoVals[2].innerHTML = p.coming_hours_html;
        } else {
          const item = comingInfoVals[2].closest(".info-item");
          if (item) item.style.display = "none";
        }
      }
      if (comingInfoVals[3] && !info.instagram) {
        const item = comingInfoVals[3].closest(".info-item");
        if (item) item.style.display = "none";
      }
    }
    const comingFooterMeta = document.querySelector(".site-footer div");
    if (comingFooterMeta && comingFooterMeta.textContent.includes("Ginger")) {
      comingFooterMeta.textContent = `© 2026 ${brandName}${p.footer_city ? " · " + p.footer_city : ""}`;
    }

    // Sipariş Kanalları (.hub-grid) — Her restoran sadece kendi aktif kanallarını görür
    const hubGrid = document.querySelector(".hub-grid");
    if (hubGrid) {
      const profile = (info.profile && typeof info.profile === "object") ? info.profile : {};
      const defaultChannels = slug === "we-smash-the-burger"
        ? { yemeksepeti: "https://www.yemeksepeti.com/restaurant/rcqj/we-smash-the-burger" }
        : {};
      const channels = (profile.channels && typeof profile.channels === "object")
        ? profile.channels
        : defaultChannels;
      const waRaw = typeof profile.whatsapp === "string" ? profile.whatsapp.trim() : "";
      const waDigits = waRaw.replace(/\D/g, "");
      const waDisplay = (typeof profile.whatsapp_display === "string" && profile.whatsapp_display.trim())
        ? profile.whatsapp_display.trim()
        : waRaw;

      let visibleCount = 0;
      hubGrid.querySelectorAll(".hub-card[data-channel]").forEach(card => {
        const ch = card.getAttribute("data-channel");
        let show = false;

        if (ch === "phone") {
          if (info.phone && String(info.phone).trim()) {
            show = true;
            const cleanTel = String(info.phone).replace(/\s+/g, "");
            card.setAttribute("href", `tel:${cleanTel}`);
            const act = card.querySelector(".btn-hub-action");
            if (act) act.textContent = info.phone;
          }
        } else if (ch === "whatsapp") {
          if (waDigits) {
            show = true;
            card.setAttribute("href", `https://wa.me/${waDigits}?text=Merhaba%2C%20sipari%C5%9F%20vermek%20istiyorum.`);
            const act = card.querySelector(".btn-hub-action");
            if (act) act.textContent = waDisplay;
          }
        } else if (ch === "trendyol" || ch === "yemeksepeti" || ch === "migros") {
          const chUrl = channels[ch] ? String(channels[ch]).trim() : "";
          if (/^https?:\/\//i.test(chUrl)) {
            show = true;
            card.setAttribute("href", chUrl);
            if (ch === "trendyol") {
              const desc = card.querySelector(".hub-card-desc");
              if (desc) desc.textContent = "Bölgenize hızlı Trendyol Go kuryesiyle teslimat.";
            }
          }
        }

        card.style.display = show ? "" : "none";
        if (show) visibleCount += 1;
      });

      hubGrid.classList.remove("hub-grid--cols-1", "hub-grid--cols-2", "hub-grid--cols-3", "hub-grid--cols-4");
      if (visibleCount >= 1 && visibleCount <= 4) {
        hubGrid.classList.add(`hub-grid--cols-${visibleCount}`);
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
    let slug = window.getActiveRestaurantSlug();
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
              if (typeof window.__tenantReveal === "function") window.__tenantReveal(); else document.documentElement.style.visibility = "";
            }
          }
        } catch (e) {}
      }
      const info = await window.ensureRestaurantConfigReady();
      const finalSlug = (info && info.slug) || window.getActiveRestaurantSlug();
      renderBrandingFromInfo(info, finalSlug);
    } finally {
      if (typeof window.__tenantReveal === "function") window.__tenantReveal(); else document.documentElement.style.visibility = "";
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
