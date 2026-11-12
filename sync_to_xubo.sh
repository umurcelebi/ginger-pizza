#!/usr/bin/env bash
# ==============================================================================
# GINGER PIZZA -> XUBO PLATFORM (SIPARIS) GÜVENLİ SENKRONİZASYON SCRIPTİ
# ==============================================================================
# Bu script, gingerpizza reposundaki çok kiracılı (multi-tenant) vitrin/admin kodlarını
# xubo reposunun YALNIZCA `siparis/` alt klasörüne güvenli bir şekilde kopyalar.
# 
# GÜVENLİK KURALI:
# - xubo.app/index.html (IPTV ana sayfası) ASLA ezilmez.
# - xubo.app/restoran/ (Master platform yönetim paneli) ASLA etkilenmez.
# ==============================================================================

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/xubo-safe-sync-$$"
REPO_URL="https://github.com/umurcelebi/xubo.git"

echo "🚀 [1/5] Xubo reposu klonlanıyor..."
rm -rf "$TEMP_DIR"
git clone --depth 1 "$REPO_URL" "$TEMP_DIR"

echo "🔒 [2/5] Güvenlik Kontrolü: xubo kök index.html korunuyor mu?"
if ! grep -q "IPTV" "$TEMP_DIR/index.html"; then
  echo "❌ HATA: xubo/index.html beklenen IPTV dosyası değil! İşlem durduruldu."
  rm -rf "$TEMP_DIR"
  exit 1
fi

echo "📦 [3/5] Çok kiracılı sipariş uygulaması siparis/ klasörüne senkronize ediliyor..."
mkdir -p "$TEMP_DIR/siparis/js" "$TEMP_DIR/siparis/images"

# 1. HTML Sayfaları (Yalnızca siparis/ altına!)
cp "$SRC_DIR/onizleme.html" "$TEMP_DIR/siparis/index.html"
cp "$SRC_DIR/onizleme.html" "$TEMP_DIR/siparis/onizleme.html"
cp "$SRC_DIR/admin.html" "$TEMP_DIR/siparis/admin.html"
cp "$SRC_DIR/orders.html" "$TEMP_DIR/siparis/orders.html"
cp "$SRC_DIR/index.html" "$TEMP_DIR/siparis/hazirlaniyor.html"

# 2. JS Dosyaları
cp -r "$SRC_DIR/js/"* "$TEMP_DIR/siparis/js/"

# 3. İmajlar
if [ -d "$SRC_DIR/images" ]; then
  cp -r "$SRC_DIR/images/"* "$TEMP_DIR/siparis/images/"
fi

echo "🔍 [4/5] Değişiklikler kontrol ediliyor..."
cd "$TEMP_DIR"

# Kök index.html veya restoran klasörünün değişmediğini doğrula
if git status --porcelain | grep -E "(^\s*[MADRCU?]+\s+index\.html|^\s*[MADRCU?]+\s+restoran/)"; then
  echo "❌ KRİTİK GÜVENLİK HATASI: Senkronizasyon root index.html veya restoran/ klasörüne dokunmaya çalıştı!"
  echo "İşlem iptal ediliyor."
  rm -rf "$TEMP_DIR"
  exit 1
fi

if [ -z "$(git status --porcelain)" ]; then
  echo "✅ Zaten güncel! Gönderilecek yeni bir değişiklik yok."
  rm -rf "$TEMP_DIR"
  exit 0
fi

echo "🚀 [5/5] GitHub'a güvenle push ediliyor..."
git add siparis/
git commit -m "chore(sync): automated safe sync of siparis storefront and admin"
git push origin main

rm -rf "$TEMP_DIR"
echo "🎉 Başarıyla tamamlandı! https://xubo.app/siparis/ güncellendi, ana sayfaya dokunulmadı."
