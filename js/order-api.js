/**
 * Ginger Pizza — Sipariş, Sepet ve Realtime Karşılama API'si
 * Destekler: Supabase Realtime (Canlı Bulut Modu) & LocalStorage (Çevrimdışı/Hızlı Test)
 */

const CART_STORAGE_KEY = "ginger_pizza_cart_v1";
const ORDERS_STORAGE_KEY = "ginger_pizza_orders_v1";
const ACTIVE_ORDER_KEY = "ginger_active_order_id_v1";

// ============================================================================
// 1. SEPET YÖNETİMİ (CART)
// ============================================================================
const Cart = {
  getItems() {
    try {
      const raw = localStorage.getItem(CART_STORAGE_KEY);
      return raw ? JSON.parse(raw) : [];
    } catch (e) {
      return [];
    }
  },

  save(items) {
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(items));
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

const OrderAPI = {
  // Yeni Sipariş Oluştur
  async createOrder(customerData, cartItems) {
    // 0. Dükkan Açık/Kapalı & Yoğun Modu Ön Kontrolü (Türkiye Saati)
    if (window.StoreStatus) {
      const settings = await window.StoreStatus.getSettings();
      const status = window.StoreStatus.evaluate(settings);
      if (!status.isOpen) {
        const closedErr = new Error(status.detail || status.title || "Dükkanımız şu anda siparişe kapalıdır.");
        closedErr.code = "STORE_CLOSED";
        closedErr.storeStatus = status;
        throw closedErr;
      }
    }

    const totalAmount = cartItems.reduce((sum, i) => sum + (i.unitPrice * i.quantity), 0);
    const orderPayload = {
      customer_name: customerData.name,
      customer_phone: customerData.phone,
      delivery_type: customerData.deliveryType || "delivery", // 'delivery' veya 'takeaway'
      delivery_address: customerData.address || "Gel-Al Siparişi",
      order_notes: customerData.notes || "",
      payment_method: customerData.paymentMethod || "door_card",
      total_amount: totalAmount,
      status: "new"
    };

    let createdOrder = null;
    const sb = getSupabaseClient();

    if (sb) {
      try {
        const { data: orderRes, error: orderErr } = await sb
          .from("orders")
          .insert([orderPayload])
          .select()
          .single();

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
    }

    // Aktif sipariş ID'sini sakla (müşteri takip edebilsin)
    localStorage.setItem(ACTIVE_ORDER_KEY, createdOrder.id);
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
    const sb = getSupabaseClient();
    if (sb) {
      try {
        let { data: orders, error } = await sb
          .from("orders")
          .select("*, order_items(*)")
          .or("is_archived.is.null,is_archived.eq.false")
          .order("created_at", { ascending: false })
          .limit(100);

        // Eğer Supabase'de is_archived sütunu henüz eklenmediyse geriye dönük uyumluluk
        if (error && (error.code === "42703" || error.code === "PGRST204" || (error.message && error.message.includes("is_archived")))) {
          const fallbackRes = await sb
            .from("orders")
            .select("*, order_items(*)")
            .order("created_at", { ascending: false })
            .limit(50);
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

    return getLocalOrders().filter(o => !o.is_archived);
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
      order.status = newStatus;
      order.updated_at = new Date().toISOString();
      saveLocalOrders(localOrders);
    }

    return true;
  },

  // Müşterinin Son Aktif Sipariş ID'sini Al
  getActiveOrderId() {
    return localStorage.getItem(ACTIVE_ORDER_KEY);
  },

  clearActiveOrderId() {
    localStorage.removeItem(ACTIVE_ORDER_KEY);
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
