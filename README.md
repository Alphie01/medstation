# MedStation

Eczacılar için AI destekli ilaç ve reçete asistanı (iOS / Android + backend).

Dart monorepo (pub workspace):

| Klasör | İçerik |
|---|---|
| `packages/medstation_core` | Ortak alan modelleri, **kural motoru** (etkileşim, mükerrer madde, doz aşımı, pediatrik, eksik veri, geri çekme, reçete türü), GS1 karekod ayrıştırıcı, doz/majistral hesaplayıcılar. Saf Dart, sunucu ve uygulama aynı kodu kullanır. |
| `server` | Dart (shelf) API: kimlik doğrulama, ilaç arama/eşdeğer, reçete kontrolü, OpenAI tabanlı kaynaklı asistan, stok/SKT, duyurular, favoriler, içe aktarma betikleri. Postgres + pgvector. |
| `app` | Flutter (iOS/Android) uygulaması; tasarım referansı "MedStation — Mobil uygulama" (MedStation'ın ilk adı) canvas'ı. |

## Güvenlik ilkeleri (koda gömülü)

- Klinik kontroller **kural motorunda** ve doğrulanmış veriyle yapılır; LLM yalnızca yüklü KÜB/KT pasajlarını kaynak göstererek açıklar. Kaynağı doğrulanamayan yanıt gösterilmez.
- Veri yoksa tahmin yapılmaz: etkileşim veritabanı bağlı değilse "Etkileşim veritabanı bağlı değil — etkileşim olmadığı anlamına gelmez" bulgusu çıkar; miktar çözülemeyen üründe doz kontrolü "Veri yok" der.
- Her bulgu eczacı onayı ister (Değerlendirdim / İlaç verilmeyecek / Not) ve denetim kaydına yazılır.
- Klinik alternatifler (eşdeğerler) ile ticari/destekleyici ürünler ayrı bölüm ve renkte gösterilir.
- Örnek veri `is_sample` işaretlidir; uygulama "ÖRNEK VERİ" bandı gösterir; `MEDSTATION_ENV=prod` iken etkin örnek veri varsa **sunucu başlamaz**.
- KVKK: hasta kimliği istenmez/saklanmaz; reçete fotoğrafı cihazda OCR'lanır; LLM'e gitmeden önce TCKN/telefon/e-posta/isim çıkarılır; kontrol kayıtları `RETENTION_DAYS` sonunda silinir; tokenlar Keychain/Keystore'da.
- MEDULA/e-Nabız: yalnızca resmî yetkili entegrasyon için arayüz (`server/lib/src/medula.dart`) var; yetki yoksa `501 integration_not_authorized` döner. Kazıma/taklit yok.

## Sunucuda çalıştırma (Docker)

```bash
git clone https://github.com/Alphie01/medstation.git && cd medstation
cp server/.env.example server/.env      # JWT_SECRET (≥32 karakter) ve OPENAI_API_KEY girin
cp .env.example .env                    # CLOUDFLARE_TUNNEL_TOKEN girin
docker compose up -d --build            # db + api + updater + cloudflared (ilk çalıştırmada TİTCK verisini kendisi yükler)
curl http://localhost:25925/health
docker compose logs -f updater          # ilk TİTCK yüklemesi ~1-2 dk
```

- **Alan adı (Cloudflare Tunnel):** kök dizinde `cp .env.example .env`, `CLOUDFLARE_TUNNEL_TOKEN` değerini girin (`COMPOSE_PROFILES=tunnel` tüneli açar). Cloudflare Zero Trust › Networks › Tunnels'ta tünele *public hostname* ekleyin: örn. `api.alanadiniz.com` → servis `http://api:8787`. TLS Cloudflare'de sonlanır; sunucuda port açmaya gerek yoktur.
- Tünel kullanılırken `API_BIND=127.0.0.1` ile API yalnızca sunucu içinden ve tünelden erişilebilir olur. Tünelsiz doğrudan erişim için `API_BIND=0.0.0.0`, port `API_PORT` (varsayılan **25925**).
- Postgres yalnızca `127.0.0.1:${DB_PORT:-5433}` üzerinde dinler; dışarıdan erişilemez, sunucudaki diğer projelerle çakışmaz.
- Gizli değerler yalnızca `server/.env` dosyasındadır (git'e girmez).
- **Otomatik güncelleme (`updater` servisi):** açılışta ve her `SYNC_EVERY` (varsayılan 6 saat) sürede TİTCK [Ruhsatlı Ürünler](https://www.titck.gov.tr/dinamikmodul/85) ve [SKRS](https://www.titck.gov.tr/dinamikmodul/43) sayfalarındaki en yeni XLSX'i bulur; daha önce içe aktarılandan farklıysa indirip tek işlemde yükler (yeni liste tamamen yazılana kadar eski liste geçerli kalır). Duyurular her çalışmada yenilenir, eskiler korunur. Okunan ürün sayısı şüpheli derecede azsa (dosya yapısı değişmişse) mevcut veri korunur ve çalışma "error" olarak kaydedilir. Çalışmalar `sync_runs` tablosunda ve uygulamada *Veri kaynakları* ekranında görünür.
  ```bash
  docker compose logs -f updater          # izleme
  docker compose exec updater sync_titck --once            # elle tetikleme
  docker compose exec updater sync_titck --once --force    # dosya aynı olsa da yeniden yükle
  ```
- İlk kullanıcı: `docker compose exec api create_user --email ... --name "..." --password "..." --pharmacy "..."`
- KÜB/KT (asistan): `docker compose exec api sh -c 'fetch_kubkt --out /tmp/kub --query "PAROL 500 MG TABLET" && ingest_documents --manifest /tmp/kub/manifest.json --version 2026-10-20'`
- Elle içe aktarma (isteğe bağlı): `ingest_titck --ruhsatli dosya.xlsx --ruhsatli-version … --skrs dosya.xlsx --skrs-version …`
- Üretimde `server/.env` içinde `MEDSTATION_ENV=prod` kullanın.

## Uygulama yapılandırması

```bash
cd app
cp .env.example .env        # API_BASE=https://api.alanadiniz.com (Cloudflare tüneli)
flutter run --dart-define-from-file=.env
```

Release derlemesi yalnızca `https://` API kabul eder; tünel ile bu sağlanır. Tünelsiz `http://IP:port` testi için `.env` içinde `ALLOW_INSECURE_HTTP=true`.

## Yerel geliştirme

```bash
docker compose up -d db                       # Postgres 16 + pgvector, 127.0.0.1:5433
cd server
cp .env.example .env                          # JWT_SECRET'ı değiştirin, OPENAI_API_KEY ekleyin
set -a; . ./.env; set +a
dart run bin/seed_dev.dart                    # SADECE geliştirme: örnek veri (ÖRNEK VERİ etiketli)
dart run bin/create_user.dart --email eczaci@etken.dev --name "Dev Eczacı" \
  --password "etken-dev-2026" --pharmacy "Dev Eczanesi"
dart run bin/server.dart                      # http://0.0.0.0:8787 (8080 Apache'de dolu)
```

### Gerçek cihazda çalıştırma

Telefon ve Mac aynı Wi-Fi ağında olmalı. Telefon `localhost`'a ulaşamaz; Mac'in yerel IP'sini verin:

```bash
ipconfig getifaddr en0                        # ör. 192.168.1.176
cd app
flutter run -d <cihaz-id> --dart-define=API_BASE=http://192.168.1.176:8787   # veya .env ile --dart-define-from-file=.env
```

- **iOS:** İlk seferde `app/ios/Runner.xcworkspace`'i Xcode'da açıp *Signing & Capabilities* altında Team seçin. Telefonda Ayarlar › Genel › VPN ve Aygıt Yönetimi'nden geliştiriciye güvenin. Uygulama ilk açılışta "yerel ağ" izni isterse izin verin.
- **Android:** USB hata ayıklamayı açın. Debug derlemesi http'ye izin verir; release derlemesi yalnızca `https://` API_BASE kabul eder.
- macOS güvenlik duvarı açıksa `dart` için gelen bağlantılara izin verin.
- Dev girişi: `eczaci@etken.dev` / `etken-dev-2026`. Örnek karekod/barkod: seed çıktısındaki `200…` barkodları (GS1 iç kullanım öneki; gerçek ürünle çakışmaz).

## Gerçek veri yükleme

İlaç listesi **tek ve ortak** bir tabloda tutulur; tüm eczaneler (tenant) aynı veriyi kullanır, cihaza kopyalanmaz. Stok, favoriler, destekleyici ürün kataloğu ve reçete kontrol kayıtları eczane (`pharmacy_id`) bazındadır; bir eczanede birden çok kullanıcı olabilir ve her işlem yapan kullanıcıyla kaydedilir.

| Veri | Kaynak | Komut |
|---|---|---|
| İlaç listesi (barkod, ürün adı, etkin madde, ATC, ruhsat sahibi, ruhsat askı durumu) | [Ruhsatlı Beşeri Tıbbi Ürünler Listesi](https://www.titck.gov.tr/dinamikmodul/85) | `dart run bin/ingest_titck.dart --ruhsatli ruhsatli.xlsx --ruhsatli-version 2026-10-16 --skrs skrs.xlsx --skrs-version 2026-10-13 [--dry-run]` |
| Reçete türü, aktif/pasif | [SKRS E-Reçete İlaç Listesi](https://www.titck.gov.tr/dinamikmodul/43) | aynı komutta `--skrs` |
| Duyurular / geri çekme / fiyat | [TİTCK duyurular](https://www.titck.gov.tr/duyuru) | `dart run bin/ingest_announcements.dart --page https://www.titck.gov.tr/duyuru --pages 3` |
| KÜB/KT metinleri (asistan) | [TİTCK KÜB/KT](https://www.titck.gov.tr/kubkt) onaylı PDF'leri | `dart run bin/fetch_kubkt.dart --out kub --query "PAROL 500 MG TABLET" …` → `dart run bin/ingest_documents.dart --manifest kub/manifest.json --version …` (`pdftotext` ve OPENAI_API_KEY gerekir; bir KÜB, adı onunla başlayan tüm ambalajlara bağlanır) |
| Etkileşim / doz sınırı | lisanslı kaynak | `dart run bin/import_clinical.dart --kind interactions --file x.json --source "…" --version … --coverage maddeler.txt` |

İçe aktarma kuralları (veri tahmin edilmez):
- Etkin madde yalnızca açık ayraçlarla (`,` `+` `/` ` ve ` ` and `) bölünür; ATC açıklaması, aşı suşu ya da ayraçsız birleşik metin "ayrıştırılamadı" olarak **kaynak metniyle** saklanır, kontrol listesinde "doğrulanamadı" çıkar.
- Madde miktarı yalnızca tek etkenli ürünlerde ürün adından alınır; kombine ürünlerde ad içindeki sıra güvenilir olmadığı için miktar boş kalır.
- Kontrol hanesi hatalı barkodlar kaynaktaki gibi alınır ve raporlanır. Fiyat (PSF) bu listelerde yoktur; "Veri yok" gösterilir.
- Geri çekme duyurularında barkod yazmıyorsa ürün otomatik eşlenmez (yanlış ürüne uyarı riski); duyuru akışında görünür.

19.10.2026 itibarıyla yüklenen: 23.044 ürün (15.331 tek etkenli miktarlı, 404 bileşimi kaynak metinli, 836 ruhsatı askıda), 30 TİTCK duyurusu, örnek olarak 5 ürünün KÜB/KT'si.

## AI asistan

- Model `OPENAI_MODEL` (varsayılan `gpt-5-nano`), `OPENAI_REASONING_EFFORT=low`; embedding `text-embedding-3-small`.
- Akış: kimlik bilgisi temizleme → pgvector'de KÜB/KT pasaj arama → yapılandırılmış yanıt (Responses API, strict JSON schema) → sunucuda kaynak doğrulama.
- Getirilmeyen pasaja atıf yapan yanıt gösterilmez; model "pasajlarda yok" derse kaynak listelenmez.
- `POST /assistant/ask/stream` aşamaları SSE ile bildirir; yanıt metni doğrulamadan sonra tek parça gelir.

Üretime geçmeden önce: örnek veriyi devre dışı bırakın (`UPDATE data_sources SET active=false WHERE is_sample`), `MEDSTATION_ENV=prod`, ≥32 karakter `JWT_SECRET`, TLS arkasında yayın, OpenAI ile veri işleme sözleşmesi (DPA).

## Uygulama simgesi

`app/tool/app_icon_test.dart` simgeyi marka renkleriyle koddan çizer (lacivert zemin, mercan/mavi kapsül, amber tablet). Yeniden üretmek için:

```bash
cd app && flutter test tool/app_icon_test.dart && dart run flutter_launcher_icons
```

## Testler

```bash
cd packages/medstation_core && dart test           # kural motoru, GS1, hesaplayıcılar, arama
cd server && dart test test/unit_test.dart
cd server && TEST_DATABASE_URL='postgresql://etken:etken@localhost:5433/etken_test?sslmode=disable' dart test
cd app && flutter analyze && flutter test test   # ekran görüntü testleri: test/goldens/
```

## Yapılmayanlar / sonraki adımlar

- Etkileşim veritabanı ve ticari ürün kataloğu bağlı değil (lisans gerektirir); arayüz bunu açıkça gösteriyor.
- MEDULA entegrasyonu yetki/protokol gerektirir; adaptör noktası hazır.
- Asistan: ilerleme aşamaları SSE ile canlı gelir; yanıt metni kaynak doğrulamasından sonra tek parça gösterilir (doğrulanmamış metin akıtılmaz).
- İlaç verisi bilinçli olarak cihazda tutulmaz; uygulama sunucuya bağlı çalışır.
- PSF/fiyat için TİTCK fiyat listesi kaynağı henüz bağlanmadı.
