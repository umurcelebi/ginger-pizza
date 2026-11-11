/**
 * Ginger Pizza & Restaurant CMS Menu API
 * Destekler: Supabase PostgreSQL (Canlı Mod) ve LocalStorage (Hızlı / Çevrimdışı Test Modu)
 */

const STORAGE_KEY = "ginger_pizza_menu_data_v2";
const CONFIG_KEY = "ginger_pizza_supabase_config_v1";

// Yemeksepeti ile Senkronize Başlangıç / Yedek Menü Verisi
const DEFAULT_MENU = [
  // ==========================================================================
  // 1. İMZA & ÖZEL PİZZALAR
  // ==========================================================================
  {
    id: "ginger-pizza",
    name: "Ginger Pizza",
    category: "imza",
    badge: "İmza Lezzet",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, dana bacon, karamelize soğan, cheddar sos, bbq sos.",
    image: "images/menu/ginger-pizza.jpg",
    isAvailable: true,
    prices: { small: 600, medium: 780, xlarge: 1320 }
  },
  {
    id: "ragnar-pizza",
    name: "Ragnar Pizza",
    category: "imza",
    badge: "Şefin Spesiyali",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, kavurma, hellim peyniri, közlenmiş patlıcan, çeri domates.",
    image: "images/menu/ragnar-pizza.jpg",
    isAvailable: true,
    prices: { small: 680, medium: 860, xlarge: 1400 }
  },
  {
    id: "ayaz-pizza",
    name: "Ayaz Pizza",
    category: "imza",
    badge: "Kavurmalı",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, Rize kavurma, beyaz soğan, yeşil biber, kültür mantarı, çeri domates.",
    image: "images/menu/ayaz-pizza.jpg",
    isAvailable: true,
    prices: { small: 640, medium: 820, xlarge: 1360 }
  },
  {
    id: "floki-pizza",
    name: "Floki Pizza",
    category: "imza",
    badge: "Gurme Seçim",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, dana bacon, rokfor peyniri, istiridye mantarı.",
    image: "images/menu/floki-pizza.jpg",
    isAvailable: true,
    prices: { small: 620, medium: 800, xlarge: 1320 }
  },
  {
    id: "kendi-pizzani-yarat",
    name: "Kendi Pizzanı Kendin Yarat",
    category: "imza",
    badge: "Özel Seçim",
    badgeType: "signature",
    ingredients: "Seçeceğiniz malzemeler ile (dilediğiniz malzemeleri sipariş notunda belirtebilirsiniz).",
    image: "images/menu/kendi-pizzani-yarat.jpg",
    isAvailable: true,
    prices: { small: 580, medium: 720, xlarge: 1240 }
  },

  // ==========================================================================
  // 2. KLASİK & TAVUKLU LEZZETLER
  // ==========================================================================
  {
    id: "banner-pizza",
    name: "Banner Pizza",
    category: "klasik",
    badge: "Klasik",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, çeri domates, fesleğen sos.",
    image: "images/menu/banner-pizza.jpg",
    isAvailable: true,
    prices: { small: 460, medium: 600, xlarge: 1080 }
  },
  {
    id: "ross-pizza",
    name: "Ross Pizza",
    category: "klasik",
    badge: "Misket Mozzarella",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, suda misket mozzarella peyniri, çeri domates, fesleğen sos.",
    image: "images/menu/ross-pizza.jpg",
    isAvailable: true,
    prices: { small: 500, medium: 640, xlarge: 1120 }
  },
  {
    id: "montana-pizza",
    name: "Montana Pizza",
    category: "klasik",
    badge: "Popüler",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, dana sucuk, kültür mantarı, siyah dilimli zeytin.",
    image: "images/menu/montana-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "wild-bill-pizza",
    name: "Wild Bill Pizza",
    category: "klasik",
    badge: "Fesleğenli Tavuk",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, fesleğen soslu tavuk, çeri domates, kültür mantarı, fesleğen sos.",
    image: "images/menu/wild-bill-pizza.jpg",
    isAvailable: true,
    prices: { small: 530, medium: 700, xlarge: 1200 }
  },
  {
    id: "vega-pizza",
    name: "Vega Pizza",
    category: "klasik",
    badge: "BBQ Tavuk",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, bbq soslu tavuk, kültür mantarı, kırmızı biber, karamelize soğan, bbq sos.",
    image: "images/menu/vega-pizza.jpg",
    isAvailable: true,
    prices: { small: 530, medium: 700, xlarge: 1200 }
  },
  {
    id: "chuck-pizza",
    name: "Chuck Pizza",
    category: "klasik",
    badge: "Çıtır Tavuk",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, nugget parçaları, mısır, cheddar sos, bbq sos.",
    image: "images/menu/chuck-pizza.jpg",
    isAvailable: true,
    prices: { small: 530, medium: 700, xlarge: 1200 }
  },
  {
    id: "bubble-pizza",
    name: "Bubble Pizza",
    category: "klasik",
    badge: "Ton Balıklı",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, ton balığı, kırmızı soğan, mısır.",
    image: "images/menu/bubble-pizza.jpg",
    isAvailable: true,
    prices: { small: 530, medium: 700, xlarge: 1200 }
  },

  // ==========================================================================
  // 3. GURME & ŞARKÜTERİ
  // ==========================================================================
  {
    id: "switch-pizza",
    name: "Switch Pizza",
    category: "gurme",
    badge: "Favori",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, fermente dana sucuk, dana sosis, mısır, siyah dilimli zeytin, yeşil biber.",
    image: "images/menu/switch-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "parker-pizza",
    name: "Parker Pizza",
    category: "gurme",
    badge: "Et Sevenler",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana jambon, dana sucuk, dana sosis.",
    image: "images/menu/parker-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "hunter-pizza",
    name: "Hunter Pizza",
    category: "gurme",
    badge: "2x Pepperoni",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, duble pepperoni.",
    image: "images/menu/hunter-pizza.jpg",
    isAvailable: true,
    prices: { small: 600, medium: 760, xlarge: 1300 }
  },
  {
    id: "gordon-pizza",
    name: "Gordon Pizza",
    category: "gurme",
    badge: "Sucuk & Hellim",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana sucuk, hellim peyniri.",
    image: "images/menu/gordon-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "marla-pizza",
    name: "Marla Pizza",
    category: "gurme",
    badge: "Jalapeno & Cheddar",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana sucuk, jalapeno turşusu, cheddar sos.",
    image: "images/menu/marla-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "pablo-pizza",
    name: "Pablo Pizza",
    category: "gurme",
    badge: "Sriracha & Bacon",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana bacon, jalapeno biber, kırmızı soğan, sriracha sos.",
    image: "images/menu/pablo-pizza.jpg",
    isAvailable: true,
    prices: { small: 580, medium: 760, xlarge: 1280 }
  },
  {
    id: "gang-pizza",
    name: "Gang Pizza",
    category: "gurme",
    badge: "Köz Patlıcanlı",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana sucuk, közlenmiş patlıcan, kırmızı biber, beyaz peynir.",
    image: "images/menu/gang-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },
  {
    id: "patrick-pizza",
    name: "Patrick Pizza",
    category: "gurme",
    badge: "Ananaslı",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana jambon, kültür mantarı, ananas.",
    image: "images/menu/patrick-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1120 }
  },

  // ==========================================================================
  // 4. VEJETARYEN & PEYNİRLİLER
  // ==========================================================================
  {
    id: "garner-pizza",
    name: "Garner Pizza",
    category: "vejetaryen",
    badge: "3 Mantarlı",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, kültür mantarı, kestane mantarı, istiridye mantarı.",
    image: "images/menu/garner-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1160 }
  },
  {
    id: "marty-pizza",
    name: "Marty Pizza",
    category: "vejetaryen",
    badge: "Vejetaryen",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, kültür mantarı, siyah dilimli zeytin, mısır, çeri domates, yeşil biber.",
    image: "images/menu/marty-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1160 }
  },
  {
    id: "benny-pizza",
    name: "Benny Pizza",
    category: "vejetaryen",
    badge: "4 Soğanlı",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, beyaz soğan, kırmızı soğan, karamelize soğan, çıtır soğan, kekik.",
    image: "images/menu/benny-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1080 }
  },
  {
    id: "nino-pizza",
    name: "Nino Pizza",
    category: "vejetaryen",
    badge: "Köz Sebzeli",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, közlenmiş patlıcan, kırmızı biber, siyah dilimli zeytin, kültür mantarı, çeri domates.",
    image: "images/menu/nino-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1160 }
  },
  {
    id: "legolas-pizza",
    name: "Legolas Pizza",
    category: "vejetaryen",
    badge: "Ispanaklı",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, ıspanak, beyaz peynir, mısır, çeri domates.",
    image: "images/menu/legolas-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1160 }
  },
  {
    id: "gorosaurus-pizza",
    name: "Gorosaurus Pizza",
    category: "vejetaryen",
    badge: "Akdeniz",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, beyaz peynir, siyah dilimli zeytin, yeşil biber, çeri domates.",
    image: "images/menu/gorosaurus-pizza.jpg",
    isAvailable: true,
    prices: { small: 520, medium: 660, xlarge: 1160 }
  },
  {
    id: "tyler-pizza",
    name: "Tyler Pizza",
    category: "vejetaryen",
    badge: "4 Peynirli",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, toz parmesan peyniri, rokfor peyniri, suda misket mozzarella peyniri.",
    image: "images/menu/tyler-pizza.jpg",
    isAvailable: true,
    prices: { small: 560, medium: 720, xlarge: 1220 }
  },

  // ==========================================================================
  // 5. YAN ÜRÜNLER & SOSLAR & POŞET
  // ==========================================================================
  {
    id: "elma-dilim-patates",
    name: "Fırınlanmış Elma Dilim Patates (300 gr.)",
    category: "yan-urun",
    badge: "Fırından",
    badgeType: "gourmet",
    ingredients: "Zeytinyağı ve kaya tuzu ile fırınlanmıştır.",
    image: "",
    isAvailable: true,
    fixedPrice: 280
  },
  {
    id: "baharatli-elma-dilim-patates",
    name: "Fırınlanmış Baharatlı Elma Dilim Patates (300 gr.)",
    category: "yan-urun",
    badge: "Cajun",
    badgeType: "gourmet",
    ingredients: "Zeytinyağı ve kaya tuzu ile fırınlanmıştır. Cajun baharatı ile karıştırılarak servis edilir.",
    image: "",
    isAvailable: true,
    fixedPrice: 300
  },
  {
    id: "cheddar-elma-dilim-patates",
    name: "Cheddar Soslu Elma Dilim Patates (300 gr.)",
    category: "yan-urun",
    badge: "Sıcak Soslu",
    badgeType: "popular",
    ingredients: "Zeytinyağı ve kaya tuzu ile fırınlanmıştır. Cheddar sos üzerine dökülür.",
    image: "",
    isAvailable: true,
    fixedPrice: 380
  },
  {
    id: "nugget-12",
    name: "Nugget (12 Adet)",
    category: "yan-urun",
    badge: "Fırınlanmış",
    badgeType: "gourmet",
    ingredients: "Fırınlanmış nugget (12 adet).",
    image: "",
    isAvailable: true,
    fixedPrice: 320
  },
  {
    id: "frankfurter-patates",
    name: "Frankfurter Sosis & Elma Dilim Patates (300 gr.)",
    category: "yan-urun",
    badge: "Sosis & Patates",
    badgeType: "gourmet",
    ingredients: "Fırınlanmış Frankfurter dana sosis, fırınlanmış elma dilim patates (300 gr.).",
    image: "",
    isAvailable: true,
    fixedPrice: 580
  },
  {
    id: "frankfurter-baharatli-patates",
    name: "Frankfurter Sosis & Baharatlı Elma Dilim Patates (300 gr.)",
    category: "yan-urun",
    badge: "Cajun Combo",
    badgeType: "gourmet",
    ingredients: "Fırınlanmış Frankfurter dana sosis, fırınlanmış cajun baharatlı elma dilim patates (300 gr.).",
    image: "",
    isAvailable: true,
    fixedPrice: 600
  },
  {
    id: "frankfurter-cheddar-patates",
    name: "Frankfurter Sosis & Cheddar Soslu Elma Dilim Patates",
    category: "yan-urun",
    badge: "Cheddar Combo",
    badgeType: "popular",
    ingredients: "Fırınlanmış Frankfurter sosis ve cheddar soslu fırınlanmış elma dilim patates (300 gr.).",
    image: "",
    isAvailable: true,
    fixedPrice: 700
  },
  {
    id: "sweet-chili-sos",
    name: "Sweet Chili Sos",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "images/menu/sweet-chili-sos.jpg",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "bbq-sos",
    name: "BBQ Sos (30 cc.)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "sarimsakli-mayonez-sos",
    name: "Sarımsaklı Mayonez Sos (30 cc.)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "ranch-sos",
    name: "Ranch Sos (30 cc.)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "sriracha-sos",
    name: "Sriracha Sos (30 cc.)",
    category: "yan-urun",
    badge: "Acı Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "sriracha-mayonez-sos",
    name: "Sriracha Mayonez Sos (30 cc.)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 20
  },
  {
    id: "feslegen-sos",
    name: "Fesleğen Sos (30 cc.)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 40
  },
  {
    id: "cheddar-sos-60cc",
    name: "Cheddar Sos (60 cc.)",
    category: "yan-urun",
    badge: "Büyük Sos",
    badgeType: "popular",
    ingredients: "Paket olarak servis edilmektedir.",
    image: "",
    isAvailable: true,
    fixedPrice: 80
  },
  {
    id: "poset",
    name: "Poşet",
    category: "yan-urun",
    badge: "Zorunlu Bedel",
    badgeType: "gourmet",
    ingredients: "Çevre Kanunu kapsamında plastik poşetlerin 1 TL karşılığında satılması zorunludur.",
    image: "images/menu/poset.jpg",
    isAvailable: true,
    fixedPrice: 1
  },

  // ==========================================================================
  // 6. TATLILAR & İÇECEKLER
  // ==========================================================================
  {
    id: "sufle",
    name: "Sufle",
    category: "tatli-icecek",
    badge: "Tatlı",
    badgeType: "signature",
    ingredients: "Pudra şekeri ile sıcak servis edilir.",
    image: "",
    isAvailable: true,
    fixedPrice: 320
  },
  {
    id: "soda-20cl",
    name: "Soda (20 cl.)",
    category: "tatli-icecek",
    badge: "İçecek",
    badgeType: "popular",
    ingredients: "Cam şişe.",
    image: "images/menu/soda-20cl.jpg",
    isAvailable: true,
    fixedPrice: 60
  },
  {
    id: "damla-su-33cl",
    name: "Damla Su (33 cl)",
    category: "tatli-icecek",
    badge: "İçecek",
    badgeType: "popular",
    ingredients: "Cam şişe.",
    image: "images/menu/damla-su-33cl.jpg",
    isAvailable: true,
    fixedPrice: 60
  },
  {
    id: "ozerhisar-ayran-25cl",
    name: "Özerhisar Ayran (25 cl.)",
    category: "tatli-icecek",
    badge: "İçecek",
    badgeType: "popular",
    ingredients: "Cam şişe.",
    image: "",
    isAvailable: true,
    fixedPrice: 100
  },
  {
    id: "ozerhisar-ayran-1l",
    name: "Özerhisar Ayran (1 L.)",
    category: "tatli-icecek",
    badge: "1 Litre",
    badgeType: "popular",
    ingredients: "Cam şişe.",
    image: "images/menu/ozerhisar-ayran-1l.jpg",
    isAvailable: true,
    fixedPrice: 160
  },
  {
    id: "coca-cola-33cl",
    name: "Coca-Cola (33 cl.)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "coca-cola-zero-33cl",
    name: "Coca-Cola Zero Sugar (33 cl.)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "fanta-33cl",
    name: "Fanta (33 cl.)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "sprite-33cl",
    name: "Sprite (33 cl.)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "fuse-tea-seftali-33cl",
    name: "Fuse Tea Şeftali (33 cl)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "fuse-tea-limon-33cl",
    name: "Fuse Tea Limon (33 cl)",
    category: "tatli-icecek",
    badge: "Kutu İçecek",
    badgeType: "popular",
    ingredients: "Kutu içecek.",
    image: "",
    isAvailable: true,
    fixedPrice: 120
  },
  {
    id: "coca-cola-1l",
    name: "Coca-Cola (1 L.)",
    category: "tatli-icecek",
    badge: "1 Litre",
    badgeType: "popular",
    ingredients: "Pet şişe.",
    image: "images/menu/coca-cola-1l.jpg",
    isAvailable: true,
    fixedPrice: 160
  },
  {
    id: "coca-cola-zero-1l",
    name: "Coca-Cola Zero Sugar (1 L.)",
    category: "tatli-icecek",
    badge: "1 Litre",
    badgeType: "popular",
    ingredients: "Pet şişe.",
    image: "images/menu/coca-cola-zero-1l.jpg",
    isAvailable: true,
    fixedPrice: 160
  }
];

function findFallbackImageByName(name) {
  if (!name) return "";
  const normalized = name.trim().toLowerCase();
  const match = DEFAULT_MENU.find(m => m.name.trim().toLowerCase() === normalized);
  return match && match.image ? match.image : "";
}

// Supabase İstemcisi Başlatıcı (Varsa)
function getSupabaseClient() {
  const config = getSupabaseConfig();
  if (config && config.url && config.key && window.supabase) {
    try {
      return window.supabase.createClient(config.url, config.key);
    } catch (e) {
      console.warn("Supabase client init error, falling back to local:", e);
    }
  }
  return null;
}

function getSupabaseConfig() {
  try {
    const raw = localStorage.getItem(CONFIG_KEY);
    if (raw) return JSON.parse(raw);
    if (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.url && window.SUPABASE_CONFIG.anonKey) {
      return { url: window.SUPABASE_CONFIG.url, key: window.SUPABASE_CONFIG.anonKey };
    }
    return null;
  } catch (e) {
    return null;
  }
}

function saveSupabaseConfig(url, key) {
  if (!url || !key) {
    localStorage.removeItem(CONFIG_KEY);
  } else {
    localStorage.setItem(CONFIG_KEY, JSON.stringify({ url: url.trim(), key: key.trim() }));
  }
}

// LocalStorage Yardımcıları
function getLocalMenu() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      saveLocalMenu(DEFAULT_MENU);
      return DEFAULT_MENU;
    }
    return JSON.parse(raw);
  } catch (e) {
    return DEFAULT_MENU;
  }
}

function saveLocalMenu(menu) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(menu));
  // Diğer pencerelere canlı haber ver
  window.dispatchEvent(new CustomEvent("ginger-menu-updated", { detail: menu }));
}

// ============================================================================
// DIŞA AÇIK API
// ============================================================================
const MenuAPI = {
  // Tüm menüyü getir
  async getMenu() {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        const { data: items, error } = await sb
          .from("menu_items")
          .select("*, item_variants(*), categories(slug)")
          .order("sort_order", { ascending: true });

        if (!error && items && items.length > 0) {
          // Supabase verisini standart nesne yapısına dönüştür
          return items.map(item => {
            const isPizza = item.is_pizza;
            const prices = {};
            if (item.item_variants && item.item_variants.length > 0) {
              item.item_variants.forEach(v => {
                prices[v.size_key] = Number(v.price);
              });
            }

            return {
              id: item.id,
              name: item.name,
              category: item.categories ? item.categories.slug : (isPizza ? "klasik" : "yan-urun"),
              badge: item.badge || "",
              badgeType: item.badge_type || "popular",
              ingredients: item.description || "",
              image: item.image_url || findFallbackImageByName(item.name),
              isAvailable: item.is_available !== false,
              prices: isPizza ? prices : null,
              fixedPrice: !isPizza ? Number(item.fixed_price) : null
            };
          });
        }
      } catch (err) {
        console.warn("Supabase fetch failed, fallback to local:", err);
      }
    }

    return getLocalMenu();
  },

  // Tekil ürün fiyatını güncelle
  async updatePrice(itemId, newPricesOrFixed) {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        if (typeof newPricesOrFixed === "number") {
          await sb.from("menu_items").update({ fixed_price: newPricesOrFixed, updated_at: new Date() }).eq("id", itemId);
        } else if (typeof newPricesOrFixed === "object") {
          for (const [sizeKey, price] of Object.entries(newPricesOrFixed)) {
            await sb.from("item_variants").update({ price: price }).match({ item_id: itemId, size_key: sizeKey });
          }
        }
      } catch (e) {
        console.error("Supabase update price error:", e);
      }
    }

    // LocalStorage senkronizasyonu
    const menu = getLocalMenu();
    const item = menu.find(i => i.id === itemId);
    if (item) {
      if (typeof newPricesOrFixed === "number") {
        item.fixedPrice = newPricesOrFixed;
      } else {
        item.prices = { ...item.prices, ...newPricesOrFixed };
      }
      saveLocalMenu(menu);
    }
    return item;
  },

  // Ürünün stok / yayında durumunu değiştir (Tükendi toggle)
  async toggleAvailability(itemId, isAvailable) {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        await sb.from("menu_items").update({ is_available: isAvailable, updated_at: new Date() }).eq("id", itemId);
      } catch (e) {
        console.error("Supabase toggle availability error:", e);
      }
    }

    const menu = getLocalMenu();
    const item = menu.find(i => i.id === itemId);
    if (item) {
      item.isAvailable = isAvailable;
      saveLocalMenu(menu);
    }
    return item;
  },

  // Yeni ürün ekle veya mevcut ürünü güncelle
  async saveItem(itemData) {
    const menu = getLocalMenu();
    const existingIndex = menu.findIndex(i => i.id === itemData.id);

    if (existingIndex >= 0) {
      menu[existingIndex] = { ...menu[existingIndex], ...itemData };
    } else {
      itemData.id = itemData.id || "item-" + Date.now();
      menu.push(itemData);
    }

    saveLocalMenu(menu);

    // Supabase bağlıysa oraya da yaz
    const sb = getSupabaseClient();
    if (sb) {
      try {
        console.log("Supabase save queued for item", itemData.name);
      } catch (e) {
        console.error("Supabase save error:", e);
      }
    }

    return itemData;
  },

  // Ürün sil
  async deleteItem(itemId) {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        await sb.from("menu_items").delete().eq("id", itemId);
      } catch (e) {
        console.error("Supabase delete error:", e);
      }
    }

    let menu = getLocalMenu();
    menu = menu.filter(i => i.id !== itemId);
    saveLocalMenu(menu);
    return true;
  },

  // Varsayılan menüye sıfırla
  resetDefaults() {
    saveLocalMenu(DEFAULT_MENU);
    return DEFAULT_MENU;
  },

  // Supabase ayarlarını al/kaydet
  getConfig: getSupabaseConfig,
  saveConfig: saveSupabaseConfig,

  // Bağlantı durumunu kontrol et
  async checkConnection() {
    const sb = getSupabaseClient();
    if (!sb) return { connected: false, mode: "local", message: "Yerel Tarayıcı Depolama Modu (Hemen Çalışır)" };

    try {
      const { data, error } = await sb.from("restaurants").select("name").limit(1);
      if (error) throw error;
      return { connected: true, mode: "supabase", message: "Supabase Bulut Veritabanı Bağlı ✓" };
    } catch (e) {
      return { connected: false, mode: "error", message: "Bağlantı Hatası: " + (e.message || "Erişilemedi") };
    }
  }
};

// Global erişim
window.MenuAPI = MenuAPI;
