// ==============================================================================
// XUBO / GINGER PIZZA - FAZ 3: CLOUDFLARE WORKER GÜVENLİK & ÖNBELLEK BAŞLIKLARI
// ==============================================================================
// Mevcut Cloudflare Worker'ınızın `fetch(request)` yanıtını döndürmeden hemen
// önce aşağıdaki `applySecurityAndCacheHeaders(request, response)` fonksiyonunu
// çağırın:
//
//   const response = await fetch(targetRequest);
//   return applySecurityAndCacheHeaders(request, response);
// ==============================================================================

function applySecurityAndCacheHeaders(request, response) {
  const url = new URL(request.url);
  const path = url.pathname.toLowerCase();

  const headers = new Headers(response.headers);

  // 1. Temel güvenlik başlıkları
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-Frame-Options", "SAMEORIGIN");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");

  // 2. Admin, Mutfak (KDS) ve Master Panel sayfalarında 10 dk GitHub Pages önbelleğini kapat
  const isStaffOrPanelPath =
    path === "/admin" ||
    path === "/admin.html" ||
    path === "/orders" ||
    path === "/orders.html" ||
    path.startsWith("/restoran");

  if (isStaffOrPanelPath) {
    headers.set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
    headers.set("Pragma", "no-cache");
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}
