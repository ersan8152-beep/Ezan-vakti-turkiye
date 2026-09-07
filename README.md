# Ezan Vakti Türkiye — Tam Sürüm Kaynak Paketi

Bu paket önceki tasarımın daha gerçek bir uygulama sürümüdür.

### Eklenenler
- 81 il seçimi
- GPS konumu ve ters geocoding ile il/ilçe tespiti
- Namaz vakitleri API entegrasyonu
- Canlı bir sonraki vakit geri sayımı
- Yerel bildirim planlama altyapısı
- Kıble azimut hesabı (Kâbe koordinatına göre) + cihaz pusulası
- Dua ve namaz bölümleri
- Ayarlar
- Gizlilik metni taslağı
- Mağaza yayın belgeleri
- Tarayıcıda hızlı görsel önizleme

### Çalıştırma
Flutter 3.38.1+ ortamında:
1. `flutter pub get`
2. `flutter run`

### Release
Android:
`flutter build appbundle --release`

iOS:
macOS + Xcode üzerinde `flutter build ipa --release`

### Önemli
Bu sohbet ortamında Flutter SDK ve Apple/Google imzalama hesapları bulunmadığından burada doğrudan imzalı AAB/IPA üretilemez. Kaynak kod mağaza build'ine hazırlandı; AndroidManifest/Info.plist izin ekleri `docs/` klasöründedir.

Namaz vakitleri AlAdhan'ın şehir/ülke veya koordinat tabanlı API'leriyle alınabilir.
