// =====================================================================
// assetlinks
//
// Возвращает Digital Asset Links JSON для Android App Links —
// верификация Google проверит этот файл по адресу:
//   https://jokaynapesbem.beget.app/.well-known/assetlinks.json
//
// На Beget/Supabase напрямую отдать /.well-known/* нельзя (kong не
// маршрутизирует туда), поэтому функция доступна на канонических путях:
//   /functions/v1/assetlinks
//   /functions/v1/assetlinks/.well-known/assetlinks.json
//
// Чтобы Google валидатор увидел его по нужному адресу — добавьте на
// reverse-proxy / Beget правило:
//   /.well-known/assetlinks.json → /functions/v1/assetlinks
//
// SHA256-fingerprint берётся из release-keystore приложения:
//   keytool -list -v -keystore release.keystore -alias dispatcher1 \
//     | grep SHA256
// и кладётся в переменную окружения APP_LINKS_SHA256 (формат с двоеточиями).
// Если ENV пустой — функция возвращает пустой массив (App Links не
// верифицируется до момента публикации release-сборки).
// =====================================================================

const PACKAGE_NAME = "com.dispatcher1.dispatcher_1";
const SHA256 = (Deno.env.get("APP_LINKS_SHA256") ?? "").trim();

function buildAssetLinks(): unknown[] {
  if (!SHA256) return [];
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls"],
      target: {
        namespace: "android_app",
        package_name: PACKAGE_NAME,
        sha256_cert_fingerprints: [SHA256],
      },
    },
  ];
}

Deno.serve(() => {
  return new Response(JSON.stringify(buildAssetLinks()), {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
});
