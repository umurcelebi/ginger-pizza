#!/usr/bin/env bash
# ==============================================================================
# XUBO / GINGER PIZZA - A -> B ÇAPRAZ ERİŞİM & YAZMA İZOLASYON TESTİ
# ==============================================================================
# Kullanım:
#   ./cross_tenant_test.sh <admin_email> <admin_password> <hedef_diger_slug>
# Örnek:
#   ./cross_tenant_test.sh admin@wesmashtheburger.com SIFRE ginger-pizza
# ==============================================================================
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Kullanım: $0 <admin_email> <admin_password> <hedef_diger_slug>"
  exit 1
fi

ADMIN_EMAIL="$1"
ADMIN_PASS="$2"
TARGET_SLUG="$3"

BASE_URL="https://nidhfqjotaurxlqpfwqp.supabase.co"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZGhmcWpvdGF1cnhscXBmd3FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzOTUzOTYsImV4cCI6MjEwOTk3MTM5Nn0.NbZ7MotgVuisLUBwuUe0BAdvIBCLUFjWupvqmbYkZUM"

echo "🔐 [1/5] Supabase Auth ile giriş yapılıyor ($ADMIN_EMAIL)..."
AUTH_RESP=$(curl -s -X POST "$BASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}")

TOKEN=$(printf '%s' "$AUTH_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))")
if [ -z "$TOKEN" ]; then
  echo "❌ Giriş başarısız:"
  echo "$AUTH_RESP"
  exit 1
fi
echo "   ✅ JWT Token alındı."

echo "🔍 [2/5] Hedef restoran ($TARGET_SLUG) ID'si alınıyor..."
TARGET_ID=$(curl -s "$BASE_URL/rest/v1/restaurants?select=id&slug=eq.$TARGET_SLUG" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
if [ -z "$TARGET_ID" ]; then
  echo "❌ Hedef restoran bulunamadı: $TARGET_SLUG"
  exit 1
fi
echo "   ✅ Hedef ID: $TARGET_ID"

echo "🧪 [3/5] Başka restoranın sipariş & müşteri verisini okuma denemesi..."
ORD_RES=$(curl -s "$BASE_URL/rest/v1/orders?select=id&restaurant_slug=eq.$TARGET_SLUG&limit=5" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN")
CUST_RES=$(curl -s "$BASE_URL/rest/v1/customers?select=id&restaurant_slug=eq.$TARGET_SLUG&limit=5" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN")
[ "$ORD_RES" = "[]" ] || { echo "❌ HATA: Başka restoranın siparişleri okundu: $ORD_RES"; exit 1; }
[ "$CUST_RES" = "[]" ] || { echo "❌ HATA: Başka restoranın müşterileri okundu: $CUST_RES"; exit 1; }
echo "   ✅ orders=[] ve customers=[] (tamamen izole)."

echo "🧪 [4/5] Başka restoranın kategorisine / ayarlarına yazma denemesi..."
CAT_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/rest/v1/categories" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"restaurant_id\":\"$TARGET_ID\",\"slug\":\"hack-test\",\"name\":\"Hack Test\",\"sort_order\":99}")
[ "$CAT_CODE" = "401" ] || [ "$CAT_CODE" = "403" ] || { echo "❌ HATA: Başka restorana kategori yazılabildi! HTTP $CAT_CODE"; exit 1; }
echo "   ✅ Başka restorana kategori INSERT reddedildi -> HTTP $CAT_CODE"

SET_RES=$(curl -s -X PATCH "$BASE_URL/rest/v1/store_settings?id=eq.$TARGET_SLUG" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d '{"status_message":"hack-test"}')
[ "$SET_RES" = "[]" ] || { echo "❌ HATA: Başka restoranın store_settings kaydı güncellendi: $SET_RES"; exit 1; }
echo "   ✅ Başka restoranın store_settings PATCH -> 0 satır etkilendi ([])."

echo "🧪 [5/5] Başka restoran adına RPC çağrıları denemesi..."
PROF_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/rest/v1/rpc/update_my_restaurant_profile" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d "{\"p_restaurant_slug\":\"$TARGET_SLUG\",\"p_phone\":\"000\"}")
RST_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/rest/v1/rpc/reset_restaurant_history" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d "{\"p_restaurant_slug\":\"$TARGET_SLUG\"}")
SUM_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/rest/v1/rpc/get_platform_restaurants_summary" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{}')

for c in "$PROF_CODE" "$RST_CODE" "$SUM_CODE"; do
  if [ "$c" -lt 400 ]; then
    echo "❌ HATA: Çapraz RPC çağrısı beklenmedik şekilde başarılı oldu (HTTP $c)!"
    exit 1
  fi
done
echo "   ✅ update_my_restaurant_profile -> HTTP $PROF_CODE (FORBIDDEN_TENANT)"
echo "   ✅ reset_restaurant_history -> HTTP $RST_CODE (UNAUTHORIZED)"
echo "   ✅ get_platform_restaurants_summary -> HTTP $SUM_CODE (UNAUTHORIZED)"
echo "🎉 A -> B çapraz erişim ve yazma testlerinin TAMAMI başarıyla reddedildi!"
