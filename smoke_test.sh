#!/usr/bin/env bash
# ==============================================================================
# XUBO / GINGER PIZZA - FAZ 6: YAYIN ÖNCESİ OTOMATİK İZOLASYON & DUMAN TESTİ
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

SUPABASE_URL="https://nidhfqjotaurxlqpfwqp.supabase.co/rest/v1"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pZGhmcWpvdGF1cnhscXBmd3FwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQzOTUzOTYsImV4cCI6MjEwOTk3MTM5Nn0.NbZ7MotgVuisLUBwuUe0BAdvIBCLUFjWupvqmbYkZUM"

echo "🧪 [1/4] JS sözdizimi kontrolü..."
for f in js/*.js; do
  node -c "$f"
done
echo "   ✅ Tüm js/*.js dosyaları hatasız."

echo "🧪 [2/4] İstemci Supabase sorgularında gizli sütun sızıntısı kontrolü..."
if grep -rnE "\.select\([^)]*(admin_password|admin_email)" js/ onizleme.html orders.html index.html admin.html >/dev/null 2>&1; then
  echo "❌ HATA: İstemci Supabase .select() sorgularında admin_password veya admin_email bulundu!"
  grep -rnE "\.select\([^)]*(admin_password|admin_email)" js/ onizleme.html orders.html index.html admin.html
  exit 1
fi
echo "   ✅ admin_password / admin_email istemci .select() sorgularında yok."

echo "🧪 [3/4] Önbellek sürüm (?v=) tutarlılığı kontrolü..."
VERSIONS=$(grep -h "js/config\.js?v=" admin.html orders.html onizleme.html index.html | sed -E 's/.*js\/config\.js\?v=([^"]+).*/\1/' | sort -u)
VER_COUNT=$(echo "$VERSIONS" | wc -l | tr -d ' ')
if [ "$VER_COUNT" -ne 1 ]; then
  echo "❌ HATA: HTML dosyalarında farklı js/config.js?v= sürümleri var:"
  grep -n "js/config\.js" admin.html orders.html onizleme.html index.html
  exit 1
fi
echo "   ✅ Tüm HTML dosyaları aynı config sürümünü kullanıyor (v=$VERSIONS)."

echo "🧪 [4/4] Canlı Supabase anon izolasyon ve güvenlik kontrolleri..."
check_http() {
  local label="$1"
  local expected="$2"
  local method="$3"
  local path="$4"
  local data="${5:-}"
  local code
  if [ -n "$data" ]; then
    code=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "${SUPABASE_URL}${path}" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
      -H "Content-Type: application/json" -d "$data")
  else
    code=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "${SUPABASE_URL}${path}" \
      -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")
  fi
  if [ "$code" != "$expected" ]; then
    echo "❌ HATA [$label]: Beklenen HTTP $expected, gelen HTTP $code"
    exit 1
  fi
  echo "   ✅ $label -> HTTP $code"
}

check_http "restaurants.admin_password okuma" "401" "GET" "/restaurants?select=admin_password"
check_http "restaurants.admin_email okuma" "401" "GET" "/restaurants?select=admin_email"
check_http "restaurants anon PATCH" "401" "PATCH" "/restaurants?slug=eq.nonexistent-test" '{"name":"x"}'
check_http "orders anon INSERT" "401" "POST" "/orders" '{}'
check_http "RPC get_platform_restaurants_summary" "401" "POST" "/rpc/get_platform_restaurants_summary" '{}'
check_http "RPC update_my_restaurant_profile" "401" "POST" "/rpc/update_my_restaurant_profile" '{"p_restaurant_slug":"ginger-pizza"}'
check_http "RPC reset_restaurant_history" "401" "POST" "/rpc/reset_restaurant_history" '{"p_restaurant_slug":"ginger-pizza"}'
check_http "RPC clone_restaurant_menu" "401" "POST" "/rpc/clone_restaurant_menu" '{"p_target_slug":"ginger-pizza","p_source_slug":"empty"}'
check_http "RPC create_validated_order (boş slug)" "400" "POST" "/rpc/create_validated_order" '{"p_restaurant_slug":"","p_customer":{},"p_items":[]}'

echo "🎉 Tüm duman testleri başarıyla geçti!"
