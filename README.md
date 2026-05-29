# BitNet Android NDK Builder

GitHub Actions builder untuk cross-compile [microsoft/BitNet](https://github.com/microsoft/BitNet) menjadi binary Android ARM64 yang bisa dijalankan dari Termux.

Repo ini tidak mem-vendor source BitNet. Workflow akan clone upstream BitNet secara recursive, generate kernel yang dibutuhkan, build dengan Android NDK, lalu upload artifact.

## Cara pakai

1. Buka tab **Actions** di GitHub.
2. Jalankan workflow **Build BitNet for Android / Termux**.
3. Pilih input sesuai kebutuhan, lalu klik **Run workflow**.
4. Download artifact `bitnet-android-arm64-*` dari run tersebut.
5. Ekstrak artifact di Termux `$HOME`, lalu jalankan binary dari folder `bin/`.

Artifact Actions hanya berisi folder hasil build `bitnet-android-arm64/`. Arsip `.tar.gz` hanya dibuat saat build diupload ke GitHub Releases, sehingga artifact tidak menyimpan duplikat file besar.

Contoh menjalankan I2_S model di Termux:

```sh
chmod +x bin/*
./bin/llama-cli \
  -m ~/models/BitNet-b1.58-2B-4T/ggml-model-i2_s.gguf \
  -p "You are a helpful assistant" \
  -t 4 \
  -c 1024 \
  -b 1 \
  -ngl 0
```

## Catatan NDK vs Termux

- GitHub Actions memakai **Android NDK** karena build dilakukan sebagai cross-compile dari runner Linux ke Android.
- Kalau build langsung di Termux native, biasanya tidak perlu `ANDROID_NDK`; Termux sudah menyediakan clang toolchain Android.

## Artifact

Artifact berisi:

- `bin/llama-cli`
- `bin/llama-quantize`
- metadata build

Default build menggunakan `BITNET_ARM_TL1=OFF`, cocok untuk model I2_S. Jika ingin TL1 ARM kernels, jalankan workflow dengan `quant_type=tl1`.

## Releases otomatis dari tag upstream

Workflow juga berjalan terjadwal setiap 6 jam untuk mengecek tag baru di `microsoft/BitNet`.

Jika ada tag upstream yang belum punya release di repo ini, workflow akan:

1. Build tag BitNet tersebut untuk Android ARM64.
2. Upload artifact Actions untuk run tersebut.
3. Membuat GitHub Release dengan tag repo ini berbentuk `bitnet-<upstream-tag>-i2_s`.
4. Mengunggah asset `.tar.gz` ke tab **Releases**.

Saat ini upstream `microsoft/BitNet` belum memiliki tag, jadi workflow terjadwal akan skip sampai tag pertama tersedia.
