<div align="center">
  <img src="icon.png" width="128" height="128" alt="Makas Logo" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.15);">
  <h1>Makas</h1>
  <p><strong>macOS Finder için eksik olan Cmd+X (Kes) ve Cmd+V (Yapıştır / Taşı) kısayolunu sisteme kazandıran minimalist menü çubuğu uygulaması.</strong></p>
</div>

---

## 🎯 Neden Makas?

macOS Finder'da varsayılan olarak dosyaları `Cmd+X` ile kesemezsiniz. Dosya taşımak için önce `Cmd+C` ile kopyalayıp, ardından `Option+Cmd+V` kısayolu ile "Buraya Taşı" yapmanız gerekir.

**Makas**, Windows ve Linux'tan alışkın olduğunuz sezgisel kes-yapıştır akışını macOS'e kazandırır:
* **Finder'da Dosyayı Seçin:** `Cmd + X` tuşlayın (tatlı bir baloncuk sesiyle dosya kesilir).
* **Hedef Klasöre Gidin:** `Cmd + V` tuşlayın (dosya kopyalanmaz, doğrudan hedefe taşınır).
* **Vazgeçerseniz:** `Esc` veya `Cmd + C` tuşuna basarak kesme işlemini iptal edebilirsiniz.

---

## ✨ Özellikler

* **Minimalist Menü Çubuğu Tasarımı:** Menü çubuğunda sade `⌘X` simgesi ve canlı yeşil durum göstergesi (`● Makas: Aktif`).
* **Akıllı Metin Ayrımı:** Dosya adı değiştirirken (rename) veya Finder arama çubuğunda yazı yazarken metin kesme/yapıştırma işleminizi bozmaz, metinleri normal şekilde kesip yapıştırabilirsiniz.
* **Hafif Baloncuk Sesi:** `Cmd + X` yaptığınızda rahatsız etmeyen tatlı ve hafif bir baloncuk (Pop) sesi çalar.
* **Girişte Otomatik Başlat:** Bilgisayar her açıldığında arka planda otomatik başlama seçeneği.
* **Sıfır Kaynak Tüketimi:** Tamamen yerel Swift ile yazılmıştır; bellekte neredeyse hiç yer kaplamaz.

---

## 🚀 Kurulum

Projeyi klonlayıp derleme betiğini çalıştırmanız yeterlidir:

```bash
git clone https://github.com/simsekdogukan/makas.git
cd makas
chmod +x build.sh
./build.sh
```

Betiği çalıştırdığınızda uygulama `/Applications/Makas.app` olarak kurulacak ve otomatik başlatılacaktır.

### 🔐 Gerekli İzin
Finder üzerindeki klavye kısayollarını yakalayabilmek için macOS Erişilebilirlik iznine ihtiyaç duyulur:
1. **Sistem Ayarları** > **Gizlilik ve Güvenlik** > **Erişilebilirlik** bölümüne gidin.
2. **Makas** uygulamasının yanındaki anahtarı açın.
3. Menü çubuğundaki gösterge yeşile dönerek aktifleşecektir.

---

## 🛠️ Lisans

MIT License © 2026 Doğukan Şimşek
