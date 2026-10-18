# CMF Phone 1 (tetris) — LineageOS Dirty Flash Scripti

`dirty_flash.bat`, OTARipper ile çıkardığın OTA imajlarını **veri silmeden**
(dirty) flashlayan, slot farkındalıklı bir Windows scriptidir. `payload.bin`
imzalama derdi olmadan, LineageOS güncellemesini fastboot ile uygular.

## Neden bu script var — chatbot scriptindeki sorunlar

Elindeki AI scripti fena değil (fastbootd geçişi, VAB snapshot kontrolü iyi
düşünülmüş) ama güvenilir değil, çünkü:

1. **Uydurma hash'ler.** `FENRIR_HASHES` listesindeki `c480e872...` ve
   `ce6c05d0...` diye bir gerçeklik kaynağı yok. Benim scriptimdeki stock lk
   hash'i **resmi** nothing_archive `Tetris_B4.1-260928-1140-hash.sha256`
   dosyasından alınmadır:
   `06fe7a8ec097ec05c13c416ffef3989b8c85190bf6621ab0be7d509fa1543dbd`.
   Bilinmeyen her hash "UNKNOWN (fenrir olabilir)" olarak uyarır.
2. **`bl2_ext` yanlış eşlenmiş.** `bl2_ext` ayrı bir partition değildir.
   `lk_a` partition'ının içindeki paket, fenrir'in kendi README'si ve
   R0rt1z2'nin blogundaki DA dökümüne göre `lk + bl2_ext + aee + lk_main_dtb
   + lk_dtbo` imajlarından oluşur (preloader logu: `part: lk_a img: bl2_ext`).
   Yani update'teki "fenrirli lk.img" = içi patch'li bl2_ext olan lk paketidir.
   Tek başına `bl2_ext.img`'i bir yere flashlamak boot zincirini bozar;
   script bunları `[BLOCK]` gösterir, tam `lk.img`'i hash kontrolüyle sorar.
3. **`preloader_raw.img` → `preloader` eşlemesini bilmiyor.** nothing_flasher'ın
   kendi `flash_all.bat`i ve fenrir'in flash talimatı nettir:
   `fastboot flash preloader_a preloader_raw.img`. Yani dosya adı ≠ partition adı.
4. **Sessiz bloklar.** Neden flashlanmadığı anlatılmadan dosyalar atlanıyor.
   Bu scriptte her dosya plan tablosunda görünür; sadece kimlik/wipe
   partitionları sessizce engellenir (aşağıya bak).

## Neden (lk hariç) bloklanmış dosyalar vardı?

O scriptteki `bl2_ext preloader preloader_raw` bloğu aslında üç farklı
durumu karıştırıyor:

| Dosya | Gerçek durumu | Bu scriptte |
|---|---|---|
| `bl2_ext.img` | lk paketinin iç imajı, partition değil | `[BLOCK]` — tek başına flashlanmaz |
| `preloader_raw.img` | `preloader` partition'ına gider | `[ASK]` — firmware sorusunun parçası |
| `preloader.img` | aynı partition (yedek ad) | `[ASK]` — `preloader_raw` varsa o tercih edilir |

`preloader` konusundaki temkinli yaklaşım **doğru**: BootROM'dan sonra çalışan
ilk koddur, ROM güncellemesiyle ilgisi yoktur, yanlış imaj telefona **hard
brick** atar (MTK SP Flash ile ancak kurtarılır). Ama bu, sessiz blok değil
**açık bir soru + uyarı** olmalı — öyle yaptım. xiaomi.eu mantığına en yakın
davranış budur: "her şey flashlanır" dersen (3 soruya da Y) firmware dahil
her şey flashlanır; sadece aşağıdaki liste asla flashlanmaz.

**Asla flashlanmayanlar** (kimlik / wipe / cihaz durumu — xiaomi.eu scriptleri
bunları da flashlamaz, ROM zipinde zaten bulunmazlar):

`userdata metadata cache frp sdcard nvram nvdata nvcfg protect1 protect2
persist proinfo seccfg super_empty`

- `nvram/nvdata/protect*` → IMEI
- `persist` → DRM/anahtarlar
- `seccfg` → kilit durumu
- `super_empty` → `wipe-super` ile tüm super'i (yani tüm ROM'u) siler
- `userdata/metadata` → veri silme (dirty flash'te asla)

## Ekran akışı

1. **Plan tablosu**: klasördeki her `*.img` → hedef partition, `[AUTO]/[ASK]/[BLOCK]`
2. **Firmware sorusu** (varsa): modem/tee/gz/... + preloader. ROM güncellemesi
   için gerekmez; sadece tam firmware güncellemesi istiyorsan Y.
3. **lk sorusu**: SHA-256 hesaplanır, resmi stock hash ile karşılaştırılır,
   dosyada "fenrir" dizgesi aranır. UNKNOWN ise uzun uyarı + onay.
4. **Bilinmeyen isimler** (varsa): partition adını dosya adından alır, onay ister.
5. **Son onay** → Phase 1 (bootloader fastboot: firmware, lk, boot, dtbo, vbmeta*)
   → `fastboot reboot fastboot` → VAB snapshot kontrolü → Phase 2 (fastbootd:
   system, vendor, product, ... ) → `--set-active=<mevcut slot>` → `reboot`.

## lk.img konusu — fenrir

- Fenrir, `bl2_ext` içindeki `sec_get_vfy_policy()`'yi patch'leyip zinciri
  kıran bir PoC exploitidir ve **repo 20 Eylül 2026'da arşivlenmiştir**.
- Kendi release notu: *"Nothing patched this in NOS 4 stable"* — yani güncel
  B4.1 preloader'da açık kapalı; fenrir zinciri bugün çalışamaz. Senin
  "fenrir stabil değil, amacına ulaşamıyor" gözleminle birebir uyumlu.
- Fenrir'li lk flashlamak factory reset gerektirebilir (unlock mantığı).
- Unofficial LineageOS 24 tetris build'lerinden birinin manifestindeki not:
  *"fenrir patched-LK support: deliberately excluded... A stock unlocked
  bootloader does not need it."* — yani **stock unlock'lu lk yeterlidir**.
- Sonuç: update'teki fenrirli `lk.img`'i **kullanma**, nothing_archive'den
  aldığın temiz `lk.img`'i klasöre koy (şu an öyle yapmışsın). Script zaten
  hash'i doğrular, eşleşirse "KNOWN STOCK" der.

## Kullanım

1. `dirty_flash.bat`'i imajların olduğu klasöre kopyala
   (OTARipper çıktısı + stock `lk.img` yanına). Gerekirse `IMG=`'i düzenle.
2. Telefonu bootloader moduna al: `adb reboot bootloader`
3. `dirty_flash.bat`'i çalıştır, planı oku, sorulara cevap ver.
4. Biterse telefon açılır; ilk açılış birkaç dakika sürebilir.

Gereksinimler: Windows, USB sürücüsü (Android Bootloader Interface), internet
yalnızca platform-tools indirilecekse.

## Bilinçli farklar (clean `flash_all.bat`'e göre)

- `userdata`/`metadata` asla silinmez (o script sorar, bu script hiç sormaz).
- `wipe-super`/`super_empty` yok; logical partitionlar silinip yeniden
  yaratılmaz, üzerine yazılır (fastboot imaja göre otomatik boyutlar).
- Yalnızca **mevcut slot** yazılır; diğer slot'a dokunulmaz (geri dönüş
  imkanı). flash_all her şeyi slot a'ya yazar.
- VAB snapshot: `merging` ise durur (önce Android'de birleştir), bekleyen
  update varsa `snapshot-update cancel` eder.

## Sorun giderme

- **`getvar product` cihazda `k6878v1_64` döner** (MT6878 platform adı, yani
  Dimensity 7300) — bozukluk değil. Script hem `tetris` hem `k6878v1_64`
  değerlerini kabul eder.
- **fastbootd gelmiyor (Windows)**: telefon fastbootd'de yeniden enumere olur,
  sürücü takılabilir. Aygıt Yöneticisi'nden sürücüyü tazele / USB2 portu dene.
- **Snapshot merge uyarısı**: Android'i aç, Ayarlar'dan birleştirme bitsin,
  tekrar dene.
- **Yarım kaldı**: hiçbir şey silinmez; scripti tekrar çalıştır, yazılanlar
  tekrar yazılır.
- **Bootloop**: bootloader hâlâ çalışır; eski imajları veya diğer slot'u
  flashlayarak geri dönebilirsin. lk yüzündense stock `lk.img`'i geri yaz:
  `fastboot flash lk_a lk.img`
