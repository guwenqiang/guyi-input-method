# GuYi Input Method

![Logo GuYi](../assets/guyi-logo.png)

[简体中文](../README.md) · [English](README.en.md) · [Bahasa Indonesia](README.id.md)

**Berkomunikasi lintas bahasa tanpa meninggalkan kolom pengetikan.** GuYi adalah metode input (IME) native untuk Apple Silicon/macOS 26. Rime menangani Pinyin Mandarin secara lokal; API model AI pilihan Anda menampilkan terjemahan dekat kursor untuk dipilih, disalin, atau dibacakan. Teks yang dipilih di aplikasi lain juga dapat diterjemahkan di dekatnya. Kartu belajar opsional menjelaskan kosakata, IPA, tata bahasa dan contoh.

GuYi ditujukan bagi pelajar, tim lintas negara, staf dukungan, dan pengguna yang sering berganti antara Mandarin, Inggris dan Indonesia. Mode input pendek cocok untuk balasan harian; pintasan yang dapat diubah mengaktifkan komposisi kalimat penuh saat diperlukan.

> Pratinjau pengembangan. Tetap sediakan metode input sistem. Seleksi lintas aplikasi, perpindahan sumber input melalui Caps Lock, dan latensi layanan cloud belum sepenuhnya lulus pengujian. Tangkapan layar panjang maupun biasa belum tersedia di build ini. DMG dengan tanda tangan pengembangan lokal belum memakai Developer ID atau notarisasi Apple.

## Manfaat praktis

| Kegiatan | Alur biasa | Dengan GuYi |
| --- | --- | --- |
| Membalas dalam bahasa lain | Menulis, membuka penerjemah, menyalin, menempel | Melihat dan memilih terjemahan di dekat kursor |
| Memahami pesan | Menyalin lalu berpindah aplikasi | Memilih teks dan melihat terjemahan di dekatnya |
| Mempelajari ungkapan | Mencari arti, pelafalan dan tata bahasa terpisah | Membuka kartu belajar dan mendengarkan |

Akurasi bergantung pada model dan konteks. Periksa hasil penting; terjemahan dan IPA berbantuan AI tidak dijamin lebih baik daripada alat bahasa khusus.

## Fitur

- Pinyin Rime lokal, kandidat mendatar, pembelajaran frasa pribadi, kandidat kata Inggris umum dan saran emoji. Angka, desimal, pemisah ribuan, dan alamat web ditangani sesuai konteks.
- Pratinjau terjemahan dengan penyisipan eksplisit; mode pendek dan kalimat penuh. Empat belas bahasa tujuan yang dapat dipilih sendiri-sendiri, antarmuka Mandarin/Inggris/Indonesia.
- Perhitungan tepat, misalnya `5/5=` → `1`; ekspresi salah atau melampaui batas tidak diberi hasil tebakan.
- Terjemahan teks terpilih dengan bahasa tujuan yang diingat, salin terjemahan, dengarkan teks asli/terjemahan, dan kartu “Pelajari cara menggunakannya”. Tautan, angka saja, serta kunci/ID yang tampak sensitif disaring.
- Pembacaan seleksi presisi opsional saat aplikasi tidak menyediakan teks terpilih melalui sistem: setelah seleksi atau Select All, GuYi menyalin sebentar lalu memulihkan papan klip. Aktif secara bawaan dan dapat dimatikan. Aplikasi riwayat papan klip tetap mungkin mencatat perubahan singkat ini. “Salin otomatis teks asli yang dipilih” adalah sakelar terpisah dan mati secara bawaan.
- Sepuluh slot teks/gambar/berkas yang dapat dipakai ulang dan cache terjemahan lokal memori/SQLite dengan batas.

## Instalasi

1. Unduh DMG versi stabil terbaru dari tab **Releases** GitHub. Buka dan klik dua kali `GuYi-Input-Method.pkg`, lalu selesaikan lewat macOS Installer.
2. Buka **GuYi Input Method** dari Applications, atur dan uji layanan AI, lalu simpan.
3. Tambahkan GuYi melalui **System Settings → Keyboard → Text Input → Edit**. Pilih GuYi dalam kolom teks yang sesungguhnya. Tetap sediakan ABC sistem atau metode input lain.
4. Tanda tangan pengembangan lokal bukan notarisasi Apple. Jika macOS memblokir aplikasi, jangan menonaktifkan perlindungan sistem; tunggu build Developer ID yang dinotarisasi. DMG pratinjau tidak dijamin dapat dipasang di semua Mac.

Pembaruan biasa memakai jalur DMG → PKG yang sama, mempertahankan pengaturan, kamus dan cache tanpa reboot. Paket terpasang bukan bukti GuYi bekerja dalam WeChat, Office atau aplikasi lain.

## Mengatur model AI

Di **Settings → Service**, pilih protokol API, isi URL dasar, ID model dan API key untuk penyedia tersebut. Jalankan pengujian koneksi/terjemahan, lalu simpan.

| Protokol | Layanan yang sesuai | Contoh URL dasar |
| --- | --- | --- |
| Responses | OpenAI atau layanan dengan Responses API kompatibel | `https://api.openai.com/v1` |
| Chat Completions | Layanan dengan Chat Completions kompatibel OpenAI | URL dasar `/v1` dari penyedia |
| Claude / Anthropic Messages | Layanan yang mengimplementasikan Messages API | URL dasar dari dokumentasi penyedia |

“Kompatibel OpenAI” **tidak berarti hanya OpenAI**. Layanan lain dapat digunakan jika protokol, autentikasi, dan keluaran terstruktur yang diperlukan tersedia; tidak semua model yang mengaku kompatibel pasti berhasil. Cloud Volcengine Ark/Doubao dapat memakai rute Responses atau Chat Completions yang didukung dengan `https://ark.cn-beijing.volces.com/api/v3`, ID model atau endpoint `ep-` yang diaktifkan, dan API key Ark tersendiri. GuYi tidak membaca login aplikasi desktop Doubao. Konfigurasi terbaru tiap penyedia disimpan terpisah; menyimpan konfigurasi baru untuk penyedia yang sama menggantikan yang lama. Langganan ChatGPT bukan saldo API.

Kunci disimpan sebagai berkas lokal **teks biasa** dengan izin khusus pengguna. Cache tidak dienkripsi. Input, seleksi dan pembelajaran mengirim teks terkait ke layanan pilihan Anda; gunakan HTTPS tepercaya. Jangan unggah kunci, obrolan kerja atau tangkapan pribadi ke issue publik.

## Kontrol sehari-hari

| Tindakan | Bawaan |
| --- | --- |
| Kandidat Mandarin | Pinyin lalu Spasi atau `1–5`; `=`/`-` mengganti halaman saat menyusun Pinyin |
| Bahasa teks asli | `Option+0` menggilir Mandarin/Inggris/Indonesia |
| Kalimat penuh | `Control+Option+Return` mengaktifkan/menonaktifkan |
| Sisipkan terjemahan | `Option+1/2/3` untuk Mandarin/Inggris/Indonesia; atur bahasa lain di Pintasan |
| Konten tersimpan | `Control+Option+angka` menyalin; tambah `Shift` untuk meminta tempel |
| Teks terpilih | Seret atau klik dua kali; `Command+A` pada editor yang didukung |

Pintasan fitur dapat diubah atau dimatikan di Pengaturan. Pratinjau tidak mengirim pesan; pembacaan suara tidak memasukkan teks.

Panduan lengkap: [Bahasa Indonesia](help/id.md) · [English](help/en.md) · [中文](help/zh-Hans.md). Bantuan offline yang sama tersedia di aplikasi.

## Kode sumber dan lisensi

Dibuat dengan Swift, InputMethodKit, AppKit/SwiftUI, Rime dan SQLite. Build saat ini memerlukan Apple Silicon/macOS 26, toolchain Swift dan `librime` Homebrew. Direktori Vendor Rime adalah submodule dengan commit tetap: klon dengan `git clone --recurse-submodules`, atau jalankan `git submodule update --init --recursive` pada checkout yang sudah ada:

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
```

Kode milik GuYi menggunakan [Lisensi MIT](../LICENSE); dependensi dan kamus bawaan memiliki lisensi masing-masing di [pemberitahuan pihak ketiga](../THIRD_PARTY_NOTICES.md). Baca [kontribusi](../CONTRIBUTING.md) dan [keamanan](../SECURITY.md).
