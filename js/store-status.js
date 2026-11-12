/**
 * Ginger Pizza — Dükkan Durumu, Çalışma Saatleri & Yoğun Modu API
 * Ortak hesaplama motoru: onizleme.html, admin.html, orders.html ve order-api.js tarafından kullanılır.
 */

function getStoreSettingsRowId() {
  const rawSlug = window.SUPABASE_CONFIG && typeof window.SUPABASE_CONFIG.restaurantSlug === "string"
    ? window.SUPABASE_CONFIG.restaurantSlug.trim()
    : "";
  return rawSlug || "ginger-pizza";
}

function getStoreSettingsStorageKey() {
  const slug = getStoreSettingsRowId();
  return slug === "ginger-pizza"
    ? "ginger_pizza_store_settings_v1"
    : `ginger_pizza_store_settings_v1_${slug}`;
}

const STORE_SETTINGS_ROW_ID = getStoreSettingsRowId();

const STORE_DAY_NAMES = {
  "1": "Pazartesi",
  "2": "Salı",
  "3": "Çarşamba",
  "4": "Perşembe",
  "5": "Cuma",
  "6": "Cumartesi",
  "0": "Pazar"
};

const STORE_WEEK_ORDER = ["1", "2", "3", "4", "5", "6", "0"];

function createDefaultWeeklyHours() {
  return {
    "1": { enabled: true, open: "11:30", close: "23:00" },
    "2": { enabled: true, open: "11:30", close: "23:00" },
    "3": { enabled: true, open: "11:30", close: "23:00" },
    "4": { enabled: true, open: "11:30", close: "23:00" },
    "5": { enabled: true, open: "11:30", close: "23:00" },
    "6": { enabled: true, open: "11:30", close: "23:00" },
    "0": { enabled: true, open: "11:30", close: "23:00" }
  };
}

function createDefaultPaymentMethods() {
  return [
    { id: "door_card", label: "Kapıda Kredi Kartı", icon: "💳", enabled: true, isDefault: true },
    { id: "door_cash", label: "Kapıda Nakit", icon: "💵", enabled: true, isDefault: true }
  ];
}

function normalizePaymentMethods(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return createDefaultPaymentMethods();
  }
  const seen = new Set();
  const list = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (!item || typeof item !== "object") continue;
    const id = String(item.id || "").trim();
    const label = String(item.label || "").trim();
    if (!id || !label || seen.has(id)) continue;
    seen.add(id);
    list.push({
      id,
      label,
      icon: typeof item.icon === "string" ? item.icon.trim() : "",
      enabled: item.enabled !== false,
      isDefault: Boolean(item.isDefault || id === "door_card" || id === "door_cash")
    });
  }
  return list.length > 0 ? list : createDefaultPaymentMethods();
}

function createDefaultStoreSettings() {
  return {
    id: STORE_SETTINGS_ROW_ID,
    order_mode: "auto", // 'auto' | 'busy' | 'manual_open' | 'manual_closed'
    busy_until: null,
    status_message: "",
    weekly_hours: createDefaultWeeklyHours(),
    online_discount_enabled: false,
    online_discount_percent: 0,
    payment_methods: createDefaultPaymentMethods(),
    updated_at: new Date().toISOString()
  };
}

function normalizeStoreSettings(raw) {
  const defaults = createDefaultStoreSettings();
  const src = raw && typeof raw === "object" ? raw : {};
  const mode = ["auto", "busy", "manual_open", "manual_closed"].includes(src.order_mode) ? src.order_mode : "auto";
  const hours = createDefaultWeeklyHours();

  if (src.weekly_hours && typeof src.weekly_hours === "object") {
    for (const dayKey of Object.keys(hours)) {
      const incoming = src.weekly_hours[dayKey];
      if (incoming && typeof incoming === "object") {
        hours[dayKey] = {
          enabled: incoming.enabled !== false,
          open: /^\d{2}:\d{2}$/.test(incoming.open || "") ? incoming.open : "11:30",
          close: /^\d{2}:\d{2}$/.test(incoming.close || "") ? incoming.close : "23:00"
        };
      }
    }
  }

  const rawPercent = Number(src.online_discount_percent);
  const clampedPercent = Number.isFinite(rawPercent) ? Math.min(90, Math.max(0, Math.round(rawPercent * 100) / 100)) : 0;

  return {
    id: STORE_SETTINGS_ROW_ID,
    order_mode: mode,
    busy_until: src.busy_until || null,
    status_message: typeof src.status_message === "string" ? src.status_message : "",
    weekly_hours: hours,
    online_discount_enabled: Boolean(src.online_discount_enabled),
    online_discount_percent: clampedPercent,
    payment_methods: normalizePaymentMethods(src.payment_methods),
    updated_at: src.updated_at || new Date().toISOString()
  };
}

function getStoreSupabaseClient() {
  try {
    let config = null;
    const raw = localStorage.getItem(STORE_SETTINGS_CONFIG_KEY);
    if (raw) {
      config = JSON.parse(raw);
    } else if (window.SUPABASE_CONFIG && window.SUPABASE_CONFIG.url && window.SUPABASE_CONFIG.anonKey) {
      config = { url: window.SUPABASE_CONFIG.url, key: window.SUPABASE_CONFIG.anonKey };
    }
    if (config && config.url && config.key && window.supabase) {
      return window.supabase.createClient(config.url, config.key);
    }
  } catch (e) {
    console.warn("StoreStatus Supabase init error:", e);
  }
  return null;
}

function getLocalStoreSettings() {
  try {
    const key = getStoreSettingsStorageKey();
    const raw = localStorage.getItem(key);
    if (!raw) {
      const def = createDefaultStoreSettings();
      localStorage.setItem(key, JSON.stringify(def));
      return def;
    }
    return normalizeStoreSettings(JSON.parse(raw));
  } catch (e) {
    return createDefaultStoreSettings();
  }
}

function saveLocalStoreSettings(settings) {
  const normalized = normalizeStoreSettings(settings);
  normalized.updated_at = new Date().toISOString();
  const key = getStoreSettingsStorageKey();
  localStorage.setItem(key, JSON.stringify(normalized));
  window.dispatchEvent(new CustomEvent("ginger-store-status-updated", { detail: normalized }));
  return normalized;
}

function parseTimeToMinutes(hhmm) {
  const parts = String(hhmm || "00:00").split(":");
  const h = Number(parts[0]) || 0;
  const m = Number(parts[1]) || 0;
  return h * 60 + m;
}

function getIstanbulClock(date = new Date()) {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Europe/Istanbul",
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).formatToParts(date);

    const map = {};
    for (const p of parts) map[p.type] = p.value;
    const dayMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
    const dow = dayMap[map.weekday] !== undefined ? dayMap[map.weekday] : date.getDay();
    const hour = Number(map.hour === "24" ? 0 : map.hour) || 0;
    const minute = Number(map.minute) || 0;
    return {
      dow,
      minutes: hour * 60 + minute,
      timeText: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
    };
  } catch (e) {
    const hour = date.getHours();
    const minute = date.getMinutes();
    return {
      dow: date.getDay(),
      minutes: hour * 60 + minute,
      timeText: `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`
    };
  }
}

function formatIstanbulTime(isoString) {
  if (!isoString) return "";
  try {
    return new Intl.DateTimeFormat("tr-TR", {
      timeZone: "Europe/Istanbul",
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date(isoString));
  } catch (e) {
    return "";
  }
}

function findNextOpeningText(weeklyHours, dow, curMinutes) {
  for (let offset = 0; offset < 7; offset++) {
    const targetDow = (dow + offset) % 7;
    const dayCfg = weeklyHours[String(targetDow)];
    if (!dayCfg || !dayCfg.enabled) continue;

    const openMin = parseTimeToMinutes(dayCfg.open);
    const closeMin = parseTimeToMinutes(dayCfg.close);
    if (openMin === closeMin) continue;

    if (offset === 0 && curMinutes < openMin) {
      return `Bugün ${dayCfg.open}`;
    }
    if (offset > 0) {
      const label = offset === 1 ? "Yarın" : STORE_DAY_NAMES[String(targetDow)];
      return `${label} ${dayCfg.open}`;
    }
  }
  return "";
}

const StoreStatus = {
  DAY_NAMES: STORE_DAY_NAMES,
  WEEK_ORDER: STORE_WEEK_ORDER,
  createDefaultSettings: createDefaultStoreSettings,
  normalizeSettings: normalizeStoreSettings,
  getIstanbulClock,

  calculateDiscount(subtotal, rawSettings) {
    const s = normalizeStoreSettings(rawSettings);
    const cleanSub = Math.max(0, Number(subtotal) || 0);
    if (!s.online_discount_enabled || s.online_discount_percent <= 0 || cleanSub <= 0) {
      return {
        enabled: false,
        percent: 0,
        subtotal: cleanSub,
        discountAmount: 0,
        finalTotal: cleanSub
      };
    }
    const discountAmount = Math.round(cleanSub * (s.online_discount_percent / 100));
    const finalTotal = Math.max(0, cleanSub - discountAmount);
    return {
      enabled: true,
      percent: s.online_discount_percent,
      subtotal: cleanSub,
      discountAmount,
      finalTotal
    };
  },

  getPaymentMethods(settings) {
    const s = settings ? normalizeStoreSettings(settings) : getLocalStoreSettings();
    return s.payment_methods;
  },

  getEnabledPaymentMethods(settings) {
    return this.getPaymentMethods(settings).filter(m => m.enabled);
  },

  getPaymentMethodLabel(methodId, settings) {
    const id = String(methodId || "").trim();
    const list = this.getPaymentMethods(settings);
    const found = list.find(m => m.id === id);
    if (found) return found.label;
    if (id === "door_cash") return "Kapıda Nakit";
    if (id === "door_card") return "Kapıda Kredi Kartı";
    return id || "Kapıda Kredi Kartı";
  },

  getPaymentMethodDisplay(methodId, settings) {
    const id = String(methodId || "").trim();
    const list = this.getPaymentMethods(settings);
    const found = list.find(m => m.id === id);
    if (found) return `${found.icon ? found.icon + " " : ""}${found.label}`.trim();
    if (id === "door_cash") return "💵 Kapıda Nakit";
    if (id === "door_card") return "💳 Kapıda Kredi Kartı";
    return id || "Kapıda Kredi Kartı";
  },

  evaluate(rawSettings, now = new Date()) {
    const settings = normalizeStoreSettings(rawSettings);
    const clock = getIstanbulClock(now);
    const dowStr = String(clock.dow);
    const prevDowStr = String((clock.dow + 6) % 7);
    const todaySchedule = settings.weekly_hours[dowStr];
    const prevSchedule = settings.weekly_hours[prevDowStr];
    const customMsg = (settings.status_message || "").trim();

    // 1. Manuel Kapalı
    if (settings.order_mode === "manual_closed") {
      const nextOpen = findNextOpeningText(settings.weekly_hours, clock.dow, clock.minutes);
      return {
        isOpen: false,
        reason: "manual_closed",
        effectiveMode: "manual_closed",
        title: "Şu An Siparişe Kapalıyız",
        detail: customMsg || "Dükkanımız geçici olarak online siparişe kapatılmıştır. Bilgi için bizi arayabilirsiniz.",
        nextOpenText: nextOpen,
        todaySchedule,
        busyRemainingMinutes: null,
        settings
      };
    }

    // 1b. Manuel Açık (Çalışma saatinden bağımsız siparişe açık)
    if (settings.order_mode === "manual_open") {
      return {
        isOpen: true,
        reason: "manual_open",
        effectiveMode: "manual_open",
        title: "Siparişe Açık",
        detail: customMsg || "Dükkanımız şu anda online siparişe açıktır.",
        nextOpenText: "",
        todaySchedule,
        busyRemainingMinutes: null,
        settings
      };
    }

    // 2. Yoğun Modu (Süresiz veya süresi dolmamış)
    if (settings.order_mode === "busy") {
      const busyUntilMs = settings.busy_until ? new Date(settings.busy_until).getTime() : null;
      const isIndefinite = !busyUntilMs || Number.isNaN(busyUntilMs);
      const isStillBusy = isIndefinite || busyUntilMs > now.getTime();

      if (isStillBusy) {
        const remainingMin = isIndefinite ? null : Math.max(1, Math.ceil((busyUntilMs - now.getTime()) / 60000));
        const resumeTime = isIndefinite ? "" : formatIstanbulTime(settings.busy_until);
        const defaultBusyDetail = isIndefinite
          ? "Mutfak yoğunluğu nedeniyle online siparişlere geçici olarak ara verdik."
          : `Mutfak yoğunluğu nedeniyle kısa bir ara verdik. Tahmini açılış: ${resumeTime} (${remainingMin} dk).`;

        return {
          isOpen: false,
          reason: "busy",
          effectiveMode: "busy",
          title: "Yoğun Modu Aktif",
          detail: customMsg || defaultBusyDetail,
          nextOpenText: resumeTime ? `Tahmini ${resumeTime}` : "",
          todaySchedule,
          busyRemainingMinutes: remainingMin,
          busyUntilTime: resumeTime,
          settings
        };
      }
    }

    // 3. Otomatik Çalışma Saatleri Kontrolü
    let openByToday = false;
    let openByYesterdayOvernight = false;

    if (todaySchedule && todaySchedule.enabled) {
      const openMin = parseTimeToMinutes(todaySchedule.open);
      const closeMin = parseTimeToMinutes(todaySchedule.close);
      if (closeMin > openMin) {
        openByToday = clock.minutes >= openMin && clock.minutes < closeMin;
      } else if (closeMin < openMin) {
        openByToday = clock.minutes >= openMin;
      }
    }

    if (!openByToday && prevSchedule && prevSchedule.enabled) {
      const prevOpenMin = parseTimeToMinutes(prevSchedule.open);
      const prevCloseMin = parseTimeToMinutes(prevSchedule.close);
      if (prevCloseMin < prevOpenMin && clock.minutes < prevCloseMin) {
        openByYesterdayOvernight = true;
      }
    }

    if (openByToday || openByYesterdayOvernight) {
      const activeClose = openByYesterdayOvernight ? prevSchedule.close : todaySchedule.close;
      return {
        isOpen: true,
        reason: "open",
        effectiveMode: "auto",
        title: "Siparişe Açık",
        detail: `Bugün kapanış saati ${activeClose}. ${getStoreSettingsRowId() === "ginger-pizza" ? "Sıcak pizzalarımız" : "Lezzetlerimiz"} siparişe hazır.`,
        nextOpenText: "",
        todaySchedule,
        activeCloseTime: activeClose,
        busyRemainingMinutes: null,
        settings
      };
    }

    const nextOpen = findNextOpeningText(settings.weekly_hours, clock.dow, clock.minutes);
    const isClosedDay = !todaySchedule || !todaySchedule.enabled;
    const hoursMsg = isClosedDay
      ? `Bugün (${STORE_DAY_NAMES[dowStr]}) hizmet vermemekteyiz.${nextOpen ? " Sonraki açılış: " + nextOpen + "." : ""}`
      : `Çalışma saatlerimiz (${todaySchedule.open} – ${todaySchedule.close}) dışındayız.${nextOpen ? " Açılış: " + nextOpen + "." : ""}`;

    return {
      isOpen: false,
      reason: isClosedDay ? "closed_today" : "outside_hours",
      effectiveMode: "auto",
      title: "Çalışma Saatleri Dışındayız",
      detail: customMsg || hoursMsg,
      nextOpenText: nextOpen,
      todaySchedule,
      busyRemainingMinutes: null,
      settings
    };
  },

  async getSettings() {
    if (typeof window !== "undefined" && typeof window.ensureRestaurantConfigReady === "function") {
      await window.ensureRestaurantConfigReady();
    }
    const rowId = getStoreSettingsRowId();
    const sb = getStoreSupabaseClient();
    if (sb) {
      try {
        const { data, error } = await sb
          .from("store_settings")
          .select("*")
          .eq("id", rowId)
          .maybeSingle();

        if (!error && data) {
          const normalized = normalizeStoreSettings(data);
          saveLocalStoreSettings(normalized);
          return normalized;
        }
      } catch (e) {
        console.warn("StoreSettings fetch failed, using local:", e);
      }
    }
    return getLocalStoreSettings();
  },

  async saveSettings(newSettings) {
    const normalized = saveLocalStoreSettings(newSettings);
    const rowId = getStoreSettingsRowId();
    const sb = getStoreSupabaseClient();

    if (sb) {
      try {
        const payload = {
          id: rowId,
          order_mode: normalized.order_mode,
          busy_until: normalized.busy_until,
          status_message: normalized.status_message,
          weekly_hours: normalized.weekly_hours,
          online_discount_enabled: normalized.online_discount_enabled,
          online_discount_percent: normalized.online_discount_percent,
          payment_methods: normalized.payment_methods,
          updated_at: normalized.updated_at
        };

        let { data, error } = await sb
          .from("store_settings")
          .upsert([payload], { onConflict: "id" })
          .select()
          .single();

        // Veritabanında yeni sütunlar (online_discount_* veya payment_methods) henüz yoksa uyumlu kolonlarla tekrar dene
        if (error && /(online_discount|payment_methods)/i.test(String(error.message || ""))) {
          const errMsg = String(error.message || "");
          const retryPayload = { ...payload };
          if (/online_discount/i.test(errMsg)) {
            delete retryPayload.online_discount_enabled;
            delete retryPayload.online_discount_percent;
          }
          if (/payment_methods/i.test(errMsg)) {
            delete retryPayload.payment_methods;
          }
          let retry = await sb
            .from("store_settings")
            .upsert([retryPayload], { onConflict: "id" })
            .select()
            .single();
          if (retry.error && /(online_discount|payment_methods)/i.test(String(retry.error.message || ""))) {
            delete retryPayload.online_discount_enabled;
            delete retryPayload.online_discount_percent;
            delete retryPayload.payment_methods;
            retry = await sb.from("store_settings").upsert([retryPayload], { onConflict: "id" }).select().single();
          }
          if (!retry.error && retry.data) {
            return {
              settings: normalizeStoreSettings({
                ...retry.data,
                online_discount_enabled: normalized.online_discount_enabled,
                online_discount_percent: normalized.online_discount_percent,
                payment_methods: normalized.payment_methods
              }),
              synced: false,
              error
            };
          }
        }

        if (error) {
          return { settings: normalized, synced: false, error };
        }
        return { settings: normalizeStoreSettings(data), synced: true, error: null };
      } catch (e) {
        return { settings: normalized, synced: false, error: e };
      }
    }

    return { settings: normalized, synced: false, error: null };
  },

  async setOrderMode(mode, options = {}) {
    const current = await this.getSettings();
    let busyUntil = null;

    if (mode === "busy" && options.durationMinutes && Number(options.durationMinutes) > 0) {
      busyUntil = new Date(Date.now() + Number(options.durationMinutes) * 60000).toISOString();
    }

    const updated = {
      ...current,
      order_mode: mode,
      busy_until: busyUntil,
      status_message: options.statusMessage !== undefined ? options.statusMessage : ((mode === "auto" || mode === "manual_open") ? "" : current.status_message)
    };

    return await this.saveSettings(updated);
  },

  subscribe(callback) {
    const handleEvent = (e) => {
      if (e && e.detail) callback(e.detail);
      else this.getSettings().then(callback);
    };

    const handleStorage = (e) => {
      if (e.key === getStoreSettingsStorageKey()) {
        callback(getLocalStoreSettings());
      }
    };

    window.addEventListener("ginger-store-status-updated", handleEvent);
    window.addEventListener("storage", handleStorage);

    let channel = null;
    const sb = getStoreSupabaseClient();
    if (sb) {
      try {
        channel = sb
          .channel("store-settings-live")
          .on("postgres_changes", { event: "*", schema: "public", table: "store_settings" }, (payload) => {
            if (payload && payload.new) {
              if (payload.new.id && payload.new.id !== getStoreSettingsRowId()) return;
              const normalized = saveLocalStoreSettings(payload.new);
              callback(normalized);
            } else {
              this.getSettings().then(callback);
            }
          })
          .subscribe();
      } catch (e) {
        console.warn("StoreSettings realtime subscription failed:", e);
      }
    }

    return () => {
      window.removeEventListener("ginger-store-status-updated", handleEvent);
      window.removeEventListener("storage", handleStorage);
      if (channel && sb) sb.removeChannel(channel);
    };
  }
};

window.StoreStatus = StoreStatus;
