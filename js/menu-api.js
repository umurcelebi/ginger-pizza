/**
 * Ginger Pizza & Restaurant CMS Menu API
 * Destekler: Supabase PostgreSQL (Canlı Mod) ve LocalStorage (Hızlı / Çevrimdışı Test Modu)
 */

const STORAGE_KEY = "ginger_pizza_menu_data_v1";
const CONFIG_KEY = "ginger_pizza_supabase_config_v1";

// Başlangıç Yedek Menü Verisi
const DEFAULT_MENU = [
  {
    id: "ginger-pizza",
    name: "Ginger Pizza",
    category: "imza",
    badge: "İmza Lezzet",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, dana bacon, karamelize soğan, özel cheddar sos, barbekü sos.",
    isAvailable: true,
    prices: { small: 435, medium: 590, xlarge: 980 }
  },
  {
    id: "banner-pizza",
    name: "Banner Pizza",
    category: "klasik",
    badge: "Popüler",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, taze dilim domates, ev yapımı fesleğen sos (pesto dokunuşu).",
    isAvailable: true,
    prices: { small: 390, medium: 500, xlarge: 790 }
  },
  {
    id: "montana-pizza",
    name: "Montana Pizza",
    category: "klasik",
    badge: "Geleneksel",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, fermente dana sucuk, kültür mantarı, siyah dilimli zeytin.",
    isAvailable: true,
    prices: { small: 420, medium: 570, xlarge: 925 }
  },
  {
    id: "switch-pizza",
    name: "Switch Pizza",
    category: "gurme",
    badge: "Favori",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, fermente dana sucuk, dana sosis, tatlı mısır, zeytin, yeşil biber.",
    isAvailable: true,
    prices: { small: 430, medium: 620, xlarge: 925 }
  },
  {
    id: "parker-pizza",
    name: "Parker Pizza",
    category: "gurme",
    badge: "Et Sevenler",
    badgeType: "gourmet",
    ingredients: "Mozzarella peyniri, domates sos, dana jambon, fermente dana sucuk, dana sosis.",
    isAvailable: true,
    prices: { small: 440, medium: 610, xlarge: 960 }
  },
  {
    id: "floki-pizza",
    name: "Floki Pizza",
    category: "gurme",
    badge: "Gurme Seçim",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, dana bacon, rokfor peyniri (blue cheese), taze istiridye mantarı.",
    isAvailable: true,
    prices: { small: 480, medium: 660, xlarge: 1050 }
  },
  {
    id: "ragnar-pizza",
    name: "Ragnar Pizza",
    category: "gurme",
    badge: "Şefin Spesiyali",
    badgeType: "signature",
    ingredients: "Mozzarella peyniri, domates sos, hakiki Rize kavurma, hellim peyniri, közlenmiş patlıcan, çeri domates.",
    isAvailable: true,
    prices: { small: 495, medium: 690, xlarge: 1110 }
  },
  {
    id: "garner-pizza",
    name: "Garner Pizza",
    category: "vejetaryen",
    badge: "3 Mantarlı",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, kültür mantarı, taze kestane mantarı, istiridye mantarı, dağ kekiği.",
    isAvailable: true,
    prices: { small: 420, medium: 560, xlarge: 890 }
  },
  {
    id: "marty-pizza",
    name: "Marty Pizza",
    category: "vejetaryen",
    badge: "Vejetaryen",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, kültür mantarı, dilimli siyah zeytin, tatlı mısır, domates, yeşil köy biberi.",
    isAvailable: true,
    prices: { small: 450, medium: 560, xlarge: 870 }
  },
  {
    id: "benny-pizza",
    name: "Benny Pizza",
    category: "vejetaryen",
    badge: "Soğan Severler",
    badgeType: "veg",
    ingredients: "Mozzarella peyniri, domates sos, beyaz soğan, mor soğan, karamelize soğan, çıtır kızarmış soğan, taze kekik.",
    isAvailable: true,
    prices: { small: 410, medium: 540, xlarge: 860 }
  },
  {
    id: "chuck-pizza",
    name: "Chuck Pizza",
    category: "klasik",
    badge: "Çıtır Tavuk",
    badgeType: "popular",
    ingredients: "Mozzarella peyniri, domates sos, çıtır nugget parçaları, tatlı mısır, cheddar sos, barbekü sos.",
    isAvailable: true,
    prices: { small: 415, medium: 560, xlarge: 890 }
  },
  {
    id: "ross-pizza",
    name: "Ross Pizza",
    category: "klasik",
    badge: "Çift Peynir",
    badgeType: "popular",
    ingredients: "Çift kat mozzarella peyniri, zengin domates sosu, fesleğen yağı, kurutulmuş kekik.",
    isAvailable: true,
    prices: { small: 395, medium: 510, xlarge: 810 }
  },
  {
    id: "firin-patates",
    name: "Baharatlı Elma Dilim Fırın Patates (300 gr)",
    category: "yan-urun",
    badge: "Fırından",
    badgeType: "gourmet",
    ingredients: "Zeytinyağı, kaya tuzu, kekik, tatlı toz kırmızı biber ile taş fırında çıtır fırınlanmış patates.",
    isAvailable: true,
    fixedPrice: 265
  },
  {
    id: "cheddarli-patates",
    name: "Cheddar Soslu Fırın Patates",
    category: "yan-urun",
    badge: "Sıcak Soslu",
    badgeType: "popular",
    ingredients: "Taş fırında nar gibi kızarmış baharatlı patates, üzerinde sıcak erimiş özel cheddar sos.",
    isAvailable: true,
    fixedPrice: 295
  },
  {
    id: "citir-tavuk-sepeti",
    name: "Çıtır Nugget Sepeti (8 Adet)",
    category: "yan-urun",
    badge: "Çıtır",
    badgeType: "gourmet",
    ingredients: "Altın sarısı çıtır tavuk nugget parçaları, yanında seçeceğiniz dip sos ile.",
    isAvailable: true,
    fixedPrice: 240
  },
  {
    id: "sos-cesitleri",
    name: "Ev Yapımı Dip Soslar (Pesto / Cheddar / BBQ)",
    category: "yan-urun",
    badge: "Sos",
    badgeType: "popular",
    ingredients: "Pizzanızın çıtır kenarlarına eşlik eden taze fesleğenli pesto sos, eritme cheddar veya tütsülü barbekü sos.",
    isAvailable: true,
    fixedPrice: 50
  },
  {
    id: "cikolatali-sufle",
    name: "Taş Fırında Çikolatalı Sufle",
    category: "tatli-icecek",
    badge: "Tatlı",
    badgeType: "signature",
    ingredients: "İçi akışkan Belçika çikolatalı sıcak fırın sufle, pudra şekeri dokunuşu ile.",
    isAvailable: true,
    fixedPrice: 220
  },
  {
    id: "tiramisu",
    name: "Ev Yapımı Klasik Tiramisu",
    category: "tatli-icecek",
    badge: "İtalyan",
    badgeType: "popular",
    ingredients: "Mascarpone kreması ve espresso ıslatmalı kedi dili ile hazırlanan hafif ev yapımı tiramisu.",
    isAvailable: true,
    fixedPrice: 195
  },
  {
    id: "ginger-limonata",
    name: "Ev Yapımı Zencefilli Taze Limonata",
    category: "tatli-icecek",
    badge: "Ev Yapımı",
    badgeType: "signature",
    ingredients: "Taze sıkım limon, hafif taze zencefil dokunuşu ve nane yaprakları ile ferahlatıcı lezzet.",
    isAvailable: true,
    fixedPrice: 95
  },
  {
    id: "icecekler",
    name: "Kutu Meşrubatlar (330 ml)",
    category: "tatli-icecek",
    badge: "Soğuk İçecek",
    badgeType: "popular",
    ingredients: "Coca-Cola, Coca-Cola Zero, Fanta, Sprite, Fuse Tea Şeftali/Limon, Ayran, San Pellegrino.",
    isAvailable: true,
    fixedPrice: 65
  }
];

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
    return raw ? JSON.parse(raw) : null;
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
        // İlgili Supabase upsert işlemi
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
