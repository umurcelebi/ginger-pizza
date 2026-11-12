/**
 * Ginger Pizza — Sipariş, Sepet ve Realtime Karşılama API'si
 * Destekler: Supabase Realtime (Canlı Bulut Modu) & LocalStorage (Çevrimdışı/Hızlı Test)
 */

function getRestaurantSlug() {
  if (typeof window !== "undefined" && typeof window.getActiveRestaurantSlug === "function") {
    return window.getActiveRestaurantSlug();
  }
  const raw = window.SUPABASE_CONFIG && typeof window.SUPABASE_CONFIG.restaurantSlug === "string"
    ? window.SUPABASE_CONFIG.restaurantSlug.trim()
    : "";
  return raw || "ginger-pizza";
}

function getCartStorageKey() {
  const slug = getRestaurantSlug();
  return slug === "ginger-pizza" ? "ginger_pizza_cart_v1" : `ginger_pizza_cart_v1_${slug}`;
}

function getActiveOrderStorageKey() {
  const slug = getRestaurantSlug();
  return slug === "ginger-pizza" ? "ginger_active_order_id_v1" : `ginger_active_order_id_v1_${slug}`;
}

const ORDERS_STORAGE_KEY = "ginger_pizza_orders_v1";
const CUSTOMERS_STORAGE_KEY = "ginger_pizza_customers_v1";

function normalizePhone(rawPhone) {
  let digits = String(rawPhone || "").replace(/[^0-9]/g, "");
  if (!digits) return "";
  if (digits.length === 12 && digits.startsWith("90")) {
    digits = "0" + digits.slice(2);
  } else if (digits.length === 10 && digits.startsWith("5")) {
    digits = "0" + digits;
  }
  return digits;
}

function getIstanbulTodayStr() {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Istanbul",
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).format(new Date());
  } catch (e) {
    const d = new Date(Date.now() + 3 * 3600000);
    return d.toISOString().slice(0, 10);
  }
}

function toIstanbulDateStr(input) {
  if (!input) return "";
  const dt = new Date(input);
  if (Number.isNaN(dt.getTime())) return "";
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Istanbul",
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).format(dt);
  } catch (e) {
    const shifted = new Date(dt.getTime() + 3 * 3600000);
    return shifted.toISOString().slice(0, 10);
  }
}

function getIstanbulDateRangeBounds(startDateStr, endDateStr) {
  const today = getIstanbulTodayStr();
  const dateRe = /^\d{4}-\d{2}-\d{2}$/;
  let start = dateRe.test(String(startDateStr || "")) ? String(startDateStr) : today;
  let end = dateRe.test(String(endDateStr || "")) ? String(endDateStr) : start;
  if (end < start) {
    const tmp = start;
    start = end;
    end = tmp;
  }
  return {
    startDate: start,
    endDate: end,
    startIso: `${start}T00:00:00+03:00`,
    endIso: `${end}T23:59:59.999+03:00`
  };
}

// ============================================================================
// 1. SEPET YÖNETİMİ (CART)
// ============================================================================
const Cart = {
  getItems() {
    try {
      const raw = localStorage.getItem(getCartStorageKey());
      return raw ? JSON.parse(raw) : [];
    } catch (e) {
      return [];
    }
  },

  save(items) {
    localStorage.setItem(getCartStorageKey(), JSON.stringify(items));
    window.dispatchEvent(new CustomEvent("ginger-cart-updated", { detail: items }));
  },

  addItem(item, sizeKey = "medium", notesOrOptions = "") {
    const items = this.getItems();
    const isPizza = !!item.prices;
    const sizeLabels = {
      small: "Small (24-26 cm)",
      medium: "Medium (30-32 cm)",
      xlarge: "Mega / XL (40-42 cm)"
    };

    const opts = (notesOrOptions && typeof notesOrOptions === "object")
      ? notesOrOptions
      : { notes: String(notesOrOptions || "") };

    const removals = Array.isArray(opts.removals)
      ? opts.removals.map(r => String(r || "").trim()).filter(Boolean)
      : [];

    const additions = Array.isArray(opts.additions)
      ? opts.additions
          .filter(a => a && typeof a === "object" && String(a.name || "").trim())
          .map(a => ({
            name: String(a.name).trim(),
            kind: a.kind === "extra_item" ? "extra_item" : "addition",
            unitPrice: Math.max(0, Number(a.unitPrice) || 0)
          }))
      : [];

    const manualNote = typeof opts.notes === "string" ? opts.notes.trim() : "";
    const qtyToAdd = Math.max(1, parseInt(opts.quantity, 10) || 1);

    const basePrice = isPizza ? (item.prices[sizeKey] || 0) : (item.fixedPrice || 0);
    const additionsTotal = additions.reduce((sum, a) => sum + a.unitPrice, 0);
    const unitPrice = basePrice + additionsTotal;
    const sizeLabel = isPizza ? sizeLabels[sizeKey] : "Tek Porsiyon";

    // Birleşik mutfak/adisyon notu oluştur
    const noteParts = [];
    if (removals.length > 0) {
      noteParts.push(`Çıkar: ${removals.join(", ")}`);
    }
    if (additions.length > 0) {
      noteParts.push(
        `İlave: ${additions.map(a => `${a.name}${a.unitPrice > 0 ? ` (+${a.unitPrice}₺)` : ""}`).join(", ")}`
      );
    }
    if (manualNote) {
      noteParts.push(`Not: ${manualNote}`);
    }
    const combinedNotes = noteParts.join(" | ");

    const remKey = [...removals].sort().join("|").toLowerCase();
    const addKey = [...additions].map(a => `${a.name}:${a.unitPrice}`).sort().join("|").toLowerCase();
    const cartItemId = `${item.id}_${isPizza ? sizeKey : "fixed"}_${remKey}_${addKey}_${manualNote.toLowerCase()}`;

    const existing = items.find(i => i.cartItemId === cartItemId);
    if (existing) {
      existing.quantity += qtyToAdd;
    } else {
      items.push({
        cartItemId,
        id: item.id,
        name: item.name,
        isPizza,
        sizeKey: isPizza ? sizeKey : null,
        sizeLabel,
        basePrice,
        unitPrice,
        quantity: qtyToAdd,
        removals,
        additions,
        manualNote,
        notes: combinedNotes
      });
    }

    this.save(items);
    return items;
  },

  updateQuantity(cartItemId, delta) {
    let items = this.getItems();
    const item = items.find(i => i.cartItemId === cartItemId);
    if (item) {
      item.quantity += delta;
      if (item.quantity <= 0) {
        items = items.filter(i => i.cartItemId !== cartItemId);
      }
    }
    this.save(items);
    return items;
  },

  removeItem(cartItemId) {
    let items = this.getItems().filter(i => i.cartItemId !== cartItemId);
    this.save(items);
    return items;
  },

  clear() {
    this.save([]);
  },

  getTotal() {
    const items = this.getItems();
    return items.reduce((sum, item) => sum + (item.unitPrice * item.quantity), 0);
  },

  getCount() {
    const items = this.getItems();
    return items.reduce((sum, item) => sum + item.quantity, 0);
  }
};

// ============================================================================
// 2. SESLİ BİLDİRİM (WEB AUDIO API - DIŞ DOSYA GEREKTİRMEZ)
// ============================================================================
const SoundAlert = {
  ctx: null,

  init() {
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) this.ctx = new AudioCtx();
    }
    if (this.ctx && this.ctx.state === "suspended") {
      this.ctx.resume();
    }
  },

  playBell() {
    try {
      this.init();
      if (!this.ctx) return;

      const now = this.ctx.currentTime;
      // İki tonlu hoş restoran gong/zil sesi (A5 880Hz -> D6 1174Hz)
      const osc1 = this.ctx.createOscillator();
      const gain1 = this.ctx.createGain();
      osc1.type = "sine";
      osc1.frequency.setValueAtTime(880, now);
      gain1.gain.setValueAtTime(0.3, now);
      gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.8);
      osc1.connect(gain1);
      gain1.connect(this.ctx.destination);
      osc1.start(now);
      osc1.stop(now + 0.8);

      const osc2 = this.ctx.createOscillator();
      const gain2 = this.ctx.createGain();
      osc2.type = "sine";
      osc2.frequency.setValueAtTime(1174, now + 0.15);
      gain2.gain.setValueAtTime(0.35, now + 0.15);
      gain2.gain.exponentialRampToValueAtTime(0.001, now + 1.2);
      osc2.connect(gain2);
      gain2.connect(this.ctx.destination);
      osc2.start(now + 0.15);
      osc2.stop(now + 1.2);
    } catch (e) {
      console.warn("Sound error:", e);
    }
  }
};

// ============================================================================
// 3. SİPARİŞ APİ (ORDER API)
// ============================================================================
function getSupabaseClient() {
  if (window.supabase && window.SUPABASE_CONFIG) {
    try {
      return window.supabase.createClient(window.SUPABASE_CONFIG.url, window.SUPABASE_CONFIG.anonKey);
    } catch (e) {
      console.warn("Supabase init error:", e);
    }
  }
  return null;
}

function getLocalOrders() {
  try {
    const raw = localStorage.getItem(ORDERS_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch (e) {
    return [];
  }
}

function saveLocalOrders(orders) {
  localStorage.setItem(ORDERS_STORAGE_KEY, JSON.stringify(orders));
  window.dispatchEvent(new CustomEvent("ginger-orders-updated", { detail: orders }));
}

function getLocalCustomers() {
  try {
    const raw = localStorage.getItem(CUSTOMERS_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch (e) {
    return [];
  }
}

function saveLocalCustomers(customers) {
  localStorage.setItem(CUSTOMERS_STORAGE_KEY, JSON.stringify(customers));
}

function aggregateCustomersFromOrders(orders, targetSlug = getRestaurantSlug()) {
  const map = new Map();
  const sorted = [...(Array.isArray(orders) ? orders : [])]
    .filter(o => (o.restaurant_slug || "ginger-pizza") === targetSlug && o.status !== "cancelled")
    .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());

  for (const o of sorted) {
    const normPhone = normalizePhone(o.customer_phone);
    if (!normPhone) continue;
    const addr = (o.delivery_address || "").trim();
    const validAddr = addr && addr !== "Gel-Al Siparişi" ? addr : "";
    const existing = map.get(normPhone);
    const amount = Number(o.total_amount) || 0;

    if (!existing) {
      map.set(normPhone, {
        id: `local-${targetSlug}-${normPhone}`,
        restaurant_slug: targetSlug,
        phone_normalized: normPhone,
        phone_display: (o.customer_phone || normPhone).trim(),
        customer_name: (o.customer_name || "Müşteri").trim(),
        last_address: validAddr || addr,
        order_count: 1,
        total_spent: Math.round(amount * 100) / 100,
        last_order_at: o.created_at || new Date().toISOString(),
        notes: ""
      });
    } else {
      existing.order_count += 1;
      existing.total_spent = Math.round((existing.total_spent + amount) * 100) / 100;
      if ((!existing.last_address || existing.last_address === "Gel-Al Siparişi") && validAddr) {
        existing.last_address = validAddr;
      }
    }
  }
  return Array.from(map.values());
}

function syncLocalCustomerFromOrder(order) {
  if (!order || order.status === "cancelled") return;
  const slug = order.restaurant_slug || getRestaurantSlug();
  const normPhone = normalizePhone(order.customer_phone);
  if (!normPhone) return;

  const list = getLocalCustomers();
  const idx = list.findIndex(c => c.restaurant_slug === slug && c.phone_normalized === normPhone);
  const amount = Number(order.total_amount) || 0;
  const addr = (order.delivery_address || "").trim();
  const validAddr = addr && addr !== "Gel-Al Siparişi" ? addr : "";
  const orderDate = order.created_at || new Date().toISOString();

  if (idx >= 0) {
    const cur = list[idx];
    cur.phone_display = (order.customer_phone || cur.phone_display || normPhone).trim();
    cur.customer_name = (order.customer_name || cur.customer_name || "Müşteri").trim();
    if (validAddr) cur.last_address = validAddr;
    cur.order_count = Math.max(0, Number(cur.order_count) || 0) + 1;
    cur.total_spent = Math.round(((Number(cur.total_spent) || 0) + amount) * 100) / 100;
    if (!cur.last_order_at || new Date(orderDate) > new Date(cur.last_order_at)) {
      cur.last_order_at = orderDate;
    }
    list[idx] = cur;
  } else {
    list.push({
      id: `local-${slug}-${normPhone}`,
      restaurant_slug: slug,
      phone_normalized: normPhone,
      phone_display: (order.customer_phone || normPhone).trim(),
      customer_name: (order.customer_name || "Müşteri").trim(),
      last_address: validAddr || addr,
      order_count: 1,
      total_spent: Math.round(amount * 100) / 100,
      last_order_at: orderDate,
      notes: ""
    });
  }
  saveLocalCustomers(list);
}

function reconcileLocalCustomerStatusChange(order, oldStatus, newStatus) {
  if (!order || oldStatus === newStatus) return;
  const slug = order.restaurant_slug || getRestaurantSlug();
  const normPhone = normalizePhone(order.customer_phone);
  if (!normPhone) return;

  const list = getLocalCustomers();
  const idx = list.findIndex(c => c.restaurant_slug === slug && c.phone_normalized === normPhone);
  if (idx < 0) return;

  const amount = Number(order.total_amount) || 0;
  if (oldStatus !== "cancelled" && newStatus === "cancelled") {
    list[idx].order_count = Math.max(0, (Number(list[idx].order_count) || 0) - 1);
    list[idx].total_spent = Math.max(0, Math.round(((Number(list[idx].total_spent) || 0) - amount) * 100) / 100);
    saveLocalCustomers(list);
  } else if (oldStatus === "cancelled" && newStatus !== "cancelled") {
    list[idx].order_count = (Number(list[idx].order_count) || 0) + 1;
    list[idx].total_spent = Math.round(((Number(list[idx].total_spent) || 0) + amount) * 100) / 100;
    saveLocalCustomers(list);
  }
}

const OrderAPI = {
  // Yeni Sipariş Oluştur
  async createOrder(customerData, cartItems) {
    // 0. Dükkan Açık/Kapalı & Yoğun Modu Ön Kontrolü (Türkiye Saati)
    let liveSettings = null;
    if (window.StoreStatus) {
      liveSettings = await window.StoreStatus.getSettings();
      const status = window.StoreStatus.evaluate(liveSettings);
      if (!status.isOpen) {
        const closedErr = new Error(status.detail || status.title || "Dükkanımız şu anda siparişe kapalıdır.");
        closedErr.code = "STORE_CLOSED";
        closedErr.storeStatus = status;
        throw closedErr;
      }
    }

    const subtotalAmount = cartItems.reduce((sum, i) => sum + (i.unitPrice * i.quantity), 0);
    const discountInfo = window.StoreStatus
      ? window.StoreStatus.calculateDiscount(subtotalAmount, liveSettings)
      : { enabled: false, percent: 0, subtotal: subtotalAmount, discountAmount: 0, finalTotal: subtotalAmount };

    const restaurantSlug = getRestaurantSlug();
    const orderPayload = {
      restaurant_slug: restaurantSlug,
      customer_name: customerData.name,
      customer_phone: customerData.phone,
      delivery_type: customerData.deliveryType || "delivery", // 'delivery' veya 'takeaway'
      delivery_address: customerData.address || "Gel-Al Siparişi",
      order_notes: customerData.notes || "",
      payment_method: customerData.paymentMethod || "door_card",
      subtotal_amount: discountInfo.subtotal,
      discount_percent: discountInfo.percent,
      discount_amount: discountInfo.discountAmount,
      total_amount: discountInfo.finalTotal,
      status: "new"
    };

    let createdOrder = null;
    const sb = getSupabaseClient();

    if (sb) {
      try {
        let { data: orderRes, error: orderErr } = await sb
          .from("orders")
          .insert([orderPayload])
          .select()
          .single();

        // Çoklu restoran veya indirim sütunları veritabanına henüz eklenmediyse kademeli yedek payload ile dene
        if (orderErr && /(restaurant_slug|subtotal_amount|discount_percent|discount_amount)/i.test(String(orderErr.message || ""))) {
          const errMsg = String(orderErr.message || "");
          const retryPayload = { ...orderPayload };
          if (/restaurant_slug/i.test(errMsg)) {
            delete retryPayload.restaurant_slug;
          }
          if (/(subtotal_amount|discount_percent|discount_amount)/i.test(errMsg)) {
            delete retryPayload.subtotal_amount;
            delete retryPayload.discount_percent;
            delete retryPayload.discount_amount;
            if (discountInfo.discountAmount > 0) {
              retryPayload.order_notes = `${orderPayload.order_notes ? orderPayload.order_notes + " | " : ""}Online İndirim (%${discountInfo.percent}): -${discountInfo.discountAmount} ₺ (Ara Toplam: ${discountInfo.subtotal} ₺)`;
            }
          }
          let retryRes = await sb.from("orders").insert([retryPayload]).select().single();
          if (retryRes.error && /restaurant_slug/i.test(String(retryRes.error.message || ""))) {
            delete retryPayload.restaurant_slug;
            retryRes = await sb.from("orders").insert([retryPayload]).select().single();
          }
          orderRes = retryRes.data
            ? {
                ...retryRes.data,
                restaurant_slug: retryRes.data.restaurant_slug || restaurantSlug,
                subtotal_amount: orderPayload.subtotal_amount,
                discount_percent: orderPayload.discount_percent,
                discount_amount: orderPayload.discount_amount
              }
            : null;
          orderErr = retryRes.error;
        }

        if (orderErr) {
          const msg = String(orderErr.message || "");
          if (msg.includes("STORE_CLOSED") || msg.includes("STORE_BUSY") || msg.includes("STORE_OUTSIDE_HOURS")) {
            const dbClosedErr = new Error(msg.replace(/^STORE_[A-Z_]+:\s*/, ""));
            dbClosedErr.code = "STORE_CLOSED";
            throw dbClosedErr;
          }
          throw orderErr;
        }

        if (orderRes) {
          createdOrder = orderRes;

          // Sipariş kalemlerini ekle
          const itemsPayload = cartItems.map(item => ({
            order_id: createdOrder.id,
            item_name: item.name,
            size_label: item.sizeLabel || "",
            quantity: item.quantity,
            unit_price: item.unitPrice,
            total_price: item.unitPrice * item.quantity,
            item_notes: item.notes || ""
          }));

          await sb.from("order_items").insert(itemsPayload);
          createdOrder.items = itemsPayload;
        }
      } catch (err) {
        if (err && err.code === "STORE_CLOSED") {
          throw err;
        }
        console.warn("Supabase order insert failed, using fallback:", err);
      }
    }

    // Supabase yoksa veya hata verdiyse yerel depolamaya kaydet
    if (!createdOrder) {
      const localOrders = getLocalOrders();
      const orderNumber = 1000 + localOrders.length + 1;
      createdOrder = {
        id: "order-" + Date.now(),
        order_number: orderNumber,
        ...orderPayload,
        created_at: new Date().toISOString(),
        items: cartItems.map(i => ({
          item_name: i.name,
          size_label: i.sizeLabel || "",
          quantity: i.quantity,
          unit_price: i.unitPrice,
          total_price: i.unitPrice * i.quantity,
          item_notes: i.notes || ""
        }))
      };
      localOrders.unshift(createdOrder);
      saveLocalOrders(localOrders);
      syncLocalCustomerFromOrder(createdOrder);
    }

    // Aktif sipariş ID'sini sakla (müşteri takip edebilsin)
    localStorage.setItem(getActiveOrderStorageKey(), createdOrder.id);
    Cart.clear();

    return createdOrder;
  },

  // Tek Bir Siparişi Getir (Canlı Takip İçin)
  async getOrder(orderId) {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        const { data: order, error } = await sb
          .from("orders")
          .select("*, order_items(*)")
          .eq("id", orderId)
          .single();

        if (!error && order) {
          return {
            ...order,
            items: order.order_items || []
          };
        }
      } catch (e) {
        console.warn("Fetch order error:", e);
      }
    }

    const localOrders = getLocalOrders();
    return localOrders.find(o => o.id === orderId) || null;
  },

  // Aktif ve Arşivlenmemiş Siparişleri Listele (Mutfak / Admin İçin)
  async getOrders() {
    const slug = getRestaurantSlug();
    const sb = getSupabaseClient();
    if (sb) {
      try {
        let { data: orders, error } = await sb
          .from("orders")
          .select("*, order_items(*)")
          .eq("restaurant_slug", slug)
          .or("is_archived.is.null,is_archived.eq.false")
          .order("created_at", { ascending: false })
          .limit(100);

        // Eğer Supabase'de restaurant_slug veya is_archived sütunu henüz eklenmediyse geriye dönük uyumluluk
        if (error && (error.code === "42703" || error.code === "PGRST204" || /(is_archived|restaurant_slug)/i.test(String(error.message || "")))) {
          const fallbackRes = await sb
            .from("orders")
            .select("*, order_items(*)")
            .order("created_at", { ascending: false })
            .limit(100);
          orders = fallbackRes.data;
          error = fallbackRes.error;
        }

        if (!error && orders) {
          return orders.map(o => ({
            ...o,
            items: o.order_items || []
          }));
        }
      } catch (e) {
        console.warn("Fetch orders error:", e);
      }
    }

    return getLocalOrders().filter(o => !o.is_archived && (o.restaurant_slug || "ginger-pizza") === slug);
  },

  // Tamamlanan Siparişleri Arşivle (Gün Sonu Temizliği)
  async archiveOrders(orderIds) {
    if (!orderIds || orderIds.length === 0) return { success: true };

    const sb = getSupabaseClient();
    if (sb) {
      const { error } = await sb
        .from("orders")
        .update({ is_archived: true, updated_at: new Date() })
        .in("id", orderIds);

      if (error) {
        console.error("Archive orders error:", error);
        return { success: false, error };
      }
    }

    // Yerel depolamayı da güncelle
    const localOrders = getLocalOrders();
    let changed = false;
    localOrders.forEach(o => {
      if (orderIds.includes(o.id)) {
        o.is_archived = true;
        o.updated_at = new Date().toISOString();
        changed = true;
      }
    });
    if (changed) saveLocalOrders(localOrders);

    return { success: true };
  },

  // Sipariş Durumunu Güncelle (new -> preparing -> on_way -> delivered -> cancelled)
  async updateStatus(orderId, newStatus) {
    const sb = getSupabaseClient();
    if (sb) {
      try {
        await sb
          .from("orders")
          .update({ status: newStatus, updated_at: new Date() })
          .eq("id", orderId);
      } catch (e) {
        console.error("Update status error:", e);
      }
    }

    // Yerel depolamayı senkronize et
    const localOrders = getLocalOrders();
    const order = localOrders.find(o => o.id === orderId);
    if (order) {
      const oldStatus = order.status;
      order.status = newStatus;
      order.updated_at = new Date().toISOString();
      saveLocalOrders(localOrders);
      reconcileLocalCustomerStatusChange(order, oldStatus, newStatus);
    }

    return true;
  },

  // ============================================================================
  // RAPORLAMA & MÜŞTERİLER API (Admin Panel İçin)
  // ============================================================================
  getIstanbulTodayStr,
  normalizePhone,
  getRestaurantSlug,

  // Tek gün veya tarih aralığına göre tüm siparişleri (arşivlenmiş dahil) getir
  async getOrdersByDateRange(startDateStr, endDateStr) {
    const slug = getRestaurantSlug();
    const bounds = getIstanbulDateRangeBounds(startDateStr, endDateStr);
    const sb = getSupabaseClient();

    if (sb) {
      try {
        let { data: orders, error } = await sb
          .from("orders")
          .select("*, order_items(*)")
          .eq("restaurant_slug", slug)
          .gte("created_at", bounds.startIso)
          .lte("created_at", bounds.endIso)
          .order("created_at", { ascending: false })
          .limit(1500);

        if (error && (error.code === "42703" || error.code === "PGRST204" || /restaurant_slug/i.test(String(error.message || "")))) {
          const fallbackRes = await sb
            .from("orders")
            .select("*, order_items(*)")
            .gte("created_at", bounds.startIso)
            .lte("created_at", bounds.endIso)
            .order("created_at", { ascending: false })
            .limit(1500);
          orders = fallbackRes.data;
          error = fallbackRes.error;
        }

        if (!error && Array.isArray(orders)) {
          return orders.map(o => ({
            ...o,
            items: o.order_items || []
          }));
        }
      } catch (e) {
        console.warn("Report getOrdersByDateRange Supabase error, falling back to local:", e);
      }
    }

    return getLocalOrders()
      .filter(o => {
        if ((o.restaurant_slug || "ginger-pizza") !== slug) return false;
        const dStr = toIstanbulDateStr(o.created_at);
        return dStr >= bounds.startDate && dStr <= bounds.endDate;
      })
      .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());
  },

  async getOrdersByDate(dateStr) {
    return this.getOrdersByDateRange(dateStr, dateStr);
  },

  // Sipariş listesini ürün ve boyut kırılımına göre özetle (İptaller hariç)
  aggregateProductReport(orders) {
    const map = new Map();
    const validOrders = (Array.isArray(orders) ? orders : []).filter(o => o && o.status !== "cancelled");

    for (const order of validOrders) {
      const items = Array.isArray(order.items) ? order.items : (Array.isArray(order.order_items) ? order.order_items : []);
      for (const item of items) {
        const name = String(item.item_name || item.name || "Ürün").trim() || "Ürün";
        const key = name.toLocaleLowerCase("tr-TR");
        const qty = Math.max(0, Number(item.quantity) || 0);
        if (qty <= 0) continue;

        const lineRevenue = item.total_price !== undefined && item.total_price !== null
          ? (Number(item.total_price) || 0)
          : (Number(item.unit_price) || 0) * qty;

        const sizeText = String(item.size_label || item.sizeLabel || "").trim();
        let entry = map.get(key);
        if (!entry) {
          entry = {
            name,
            totalQty: 0,
            smallQty: 0,
            mediumQty: 0,
            xlargeQty: 0,
            singleQty: 0,
            revenue: 0
          };
          map.set(key, entry);
        }

        entry.totalQty += qty;
        entry.revenue = Math.round((entry.revenue + lineRevenue) * 100) / 100;

        if (/(small|küçük|\b24\b)/i.test(sizeText)) {
          entry.smallQty += qty;
        } else if (/(medium|orta|\b30\b)/i.test(sizeText)) {
          entry.mediumQty += qty;
        } else if (/(mega|\bxl\b|xlarge|büyük|\b40\b)/i.test(sizeText)) {
          entry.xlargeQty += qty;
        } else {
          entry.singleQty += qty;
        }
      }
    }

    return Array.from(map.values()).sort((a, b) => {
      if (b.totalQty !== a.totalQty) return b.totalQty - a.totalQty;
      return b.revenue - a.revenue;
    });
  },

  // Müşteri Listesini Getir (Önce hafif public.customers tablosundan, yoksa siparişlerden üret)
  async getCustomers(searchQuery = "", sortBy = "total_spent") {
    const slug = getRestaurantSlug();
    const sb = getSupabaseClient();
    let customers = null;

    if (sb) {
      try {
        const { data, error } = await sb
          .from("customers")
          .select("id, restaurant_slug, phone_normalized, phone_display, customer_name, last_address, order_count, total_spent, last_order_at, notes")
          .eq("restaurant_slug", slug)
          .order("total_spent", { ascending: false })
          .limit(1000);

        if (!error && Array.isArray(data)) {
          customers = data;
        } else if (error && (error.code === "42P01" || error.code === "PGRST205" || /customers/i.test(String(error.message || "")))) {
          // customers tablosu henüz oluşturulmadıysa siparişlerden geçici olarak hesapla
          let { data: ordData, error: ordErr } = await sb
            .from("orders")
            .select("restaurant_slug, customer_name, customer_phone, delivery_address, total_amount, status, created_at")
            .eq("restaurant_slug", slug)
            .neq("status", "cancelled")
            .order("created_at", { ascending: false })
            .limit(1500);

          if (ordErr && /restaurant_slug/i.test(String(ordErr.message || ""))) {
            const fbOrd = await sb
              .from("orders")
              .select("customer_name, customer_phone, delivery_address, total_amount, status, created_at")
              .neq("status", "cancelled")
              .order("created_at", { ascending: false })
              .limit(1500);
            ordData = fbOrd.data;
          }
          if (Array.isArray(ordData)) {
            customers = aggregateCustomersFromOrders(ordData, slug);
          }
        }
      } catch (e) {
        console.warn("getCustomers Supabase error, using local:", e);
      }
    }

    if (!customers) {
      const localList = getLocalCustomers().filter(c => (c.restaurant_slug || "ginger-pizza") === slug);
      customers = localList.length > 0
        ? localList
        : aggregateCustomersFromOrders(getLocalOrders(), slug);
    }

    const q = String(searchQuery || "").trim().toLocaleLowerCase("tr-TR");
    const qDigits = normalizePhone(q);
    let filtered = q
      ? customers.filter(c => {
          const hay = `${c.customer_name || ""} ${c.phone_display || ""} ${c.phone_normalized || ""} ${c.last_address || ""} ${c.notes || ""}`.toLocaleLowerCase("tr-TR");
          return hay.includes(q) || (qDigits && String(c.phone_normalized || "").includes(qDigits));
        })
      : [...customers];

    filtered.sort((a, b) => {
      if (sortBy === "order_count") {
        return (Number(b.order_count) || 0) - (Number(a.order_count) || 0) || (Number(b.total_spent) || 0) - (Number(a.total_spent) || 0);
      }
      if (sortBy === "last_order_at") {
        return new Date(b.last_order_at || 0).getTime() - new Date(a.last_order_at || 0).getTime();
      }
      return (Number(b.total_spent) || 0) - (Number(a.total_spent) || 0);
    });

    return filtered;
  },

  async updateCustomerNote(phoneNormalized, notes) {
    const slug = getRestaurantSlug();
    const normPhone = normalizePhone(phoneNormalized) || String(phoneNormalized || "").trim();
    const cleanNotes = String(notes || "").trim();
    if (!normPhone) return { success: false };

    let synced = false;
    const sb = getSupabaseClient();
    if (sb) {
      try {
        const { error } = await sb
          .from("customers")
          .update({ notes: cleanNotes, updated_at: new Date().toISOString() })
          .match({ restaurant_slug: slug, phone_normalized: normPhone });
        if (!error) synced = true;
      } catch (e) {
        console.warn("updateCustomerNote error:", e);
      }
    }

    const list = getLocalCustomers();
    const idx = list.findIndex(c => (c.restaurant_slug || "ginger-pizza") === slug && c.phone_normalized === normPhone);
    if (idx >= 0) {
      list[idx].notes = cleanNotes;
      saveLocalCustomers(list);
    }

    return { success: true, synced };
  },

  // Geçmiş Satışları (Siparişleri) ve Müşteri Kayıtlarını Restoran Bazlı Sıfırla
  async resetSalesAndCustomers() {
    const slug = getRestaurantSlug();

    const localOrders = getLocalOrders();
    const removedOrderIds = new Set();
    const remainingOrders = localOrders.filter(o => {
      const belongsToSlug = (o?.restaurant_slug || "ginger-pizza") === slug;
      if (belongsToSlug && o?.id != null) {
        removedOrderIds.add(String(o.id));
      }
      return !belongsToSlug;
    });
    const localDeletedOrders = localOrders.length - remainingOrders.length;
    saveLocalOrders(remainingOrders);

    const localCustomers = getLocalCustomers();
    const remainingCustomers = localCustomers.filter(c => (c?.restaurant_slug || "ginger-pizza") !== slug);
    const localDeletedCustomers = localCustomers.length - remainingCustomers.length;
    saveLocalCustomers(remainingCustomers);

    const activeOrderKey = getActiveOrderStorageKey();
    const activeOrderId = localStorage.getItem(activeOrderKey);
    if (activeOrderId && (removedOrderIds.has(String(activeOrderId)) || remainingOrders.length === 0)) {
      localStorage.removeItem(activeOrderKey);
    }

    const sb = getSupabaseClient();
    if (!sb) {
      return {
        success: true,
        synced: false,
        localCleared: true,
        deletedOrders: localDeletedOrders,
        deletedCustomers: localDeletedCustomers
      };
    }

    try {
      const rpcRes = await sb.rpc("reset_restaurant_history", { p_restaurant_slug: slug });
      if (!rpcRes.error) {
        localStorage.removeItem(activeOrderKey);
        const rpcData = rpcRes.data && typeof rpcRes.data === "object" ? rpcRes.data : {};
        return {
          success: true,
          synced: true,
          localCleared: true,
          deletedOrders: Number.isFinite(Number(rpcData.deleted_orders)) ? Number(rpcData.deleted_orders) : localDeletedOrders,
          deletedCustomers: Number.isFinite(Number(rpcData.deleted_customers)) ? Number(rpcData.deleted_customers) : localDeletedCustomers
        };
      }

      const rpcMsg = String(rpcRes.error.message || "");
      const missingRpc = rpcRes.error.code === "42883"
        || rpcRes.error.code === "PGRST202"
        || /Could not find the function/i.test(rpcMsg);

      if (!missingRpc) {
        return {
          success: false,
          synced: false,
          localCleared: true,
          deletedOrders: localDeletedOrders,
          deletedCustomers: localDeletedCustomers,
          error: rpcMsg || "Supabase sıfırlama RPC hatası"
        };
      }

      const custRes = await sb
        .from("customers")
        .delete()
        .eq("restaurant_slug", slug)
        .select("id");

      let cloudDeletedCustomers = Array.isArray(custRes.data) ? custRes.data.length : 0;
      if (custRes.error) {
        const custMsg = String(custRes.error.message || "");
        const missingCustTable = custRes.error.code === "42P01"
          || custRes.error.code === "PGRST205"
          || /does not exist|Could not find the table/i.test(custMsg);
        if (!missingCustTable) {
          return {
            success: false,
            synced: false,
            localCleared: true,
            deletedOrders: localDeletedOrders,
            deletedCustomers: localDeletedCustomers,
            error: custMsg || "Müşteri kayıtları buluttan silinemedi"
          };
        }
        cloudDeletedCustomers = 0;
      }

      let ordRes = await sb
        .from("orders")
        .delete()
        .eq("restaurant_slug", slug)
        .select("id");

      if (ordRes.error && (ordRes.error.code === "42703" || /restaurant_slug/i.test(ordRes.error.message || ""))) {
        ordRes = await sb
          .from("orders")
          .delete()
          .not("id", "is", null)
          .select("id");
      }

      if (ordRes.error) {
        return {
          success: false,
          synced: false,
          localCleared: true,
          deletedOrders: localDeletedOrders,
          deletedCustomers: cloudDeletedCustomers || localDeletedCustomers,
          error: String(ordRes.error.message || "Sipariş kayıtları buluttan silinemedi")
        };
      }

      localStorage.removeItem(activeOrderKey);
      const cloudDeletedOrders = Array.isArray(ordRes.data) ? ordRes.data.length : localDeletedOrders;
      return {
        success: true,
        synced: true,
        localCleared: true,
        deletedOrders: cloudDeletedOrders,
        deletedCustomers: cloudDeletedCustomers || localDeletedCustomers
      };
    } catch (err) {
      return {
        success: false,
        synced: false,
        localCleared: true,
        deletedOrders: localDeletedOrders,
        deletedCustomers: localDeletedCustomers,
        error: err && err.message ? err.message : String(err)
      };
    }
  },

  // Müşterinin Son Aktif Sipariş ID'sini Al
  getActiveOrderId() {
    return localStorage.getItem(getActiveOrderStorageKey());
  },

  clearActiveOrderId() {
    localStorage.removeItem(getActiveOrderStorageKey());
  },

  // Gerçek Zamanlı Dinleyici (Realtime WebSockets & Polling)
  subscribe(callback) {
    const sb = getSupabaseClient();
    let channel = null;

    if (sb && sb.channel) {
      try {
        channel = sb
          .channel("realtime-orders")
          .on(
            "postgres_changes",
            { event: "*", schema: "public", table: "orders" },
            payload => {
              callback(payload);
            }
          )
          .subscribe();
      } catch (e) {
        console.warn("Realtime subscribe error, fallback to polling:", e);
      }
    }

    // Sekmeler arası canlı dinleyici
    const localHandler = e => callback({ eventType: "LOCAL_UPDATE", data: e.detail });
    window.addEventListener("ginger-orders-updated", localHandler);

    return () => {
      if (channel && sb) sb.removeChannel(channel);
      window.removeEventListener("ginger-orders-updated", localHandler);
    };
  }
};

window.Cart = Cart;
window.OrderAPI = OrderAPI;
window.SoundAlert = SoundAlert;
