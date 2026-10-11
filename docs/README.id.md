# GuYi Input Method

![Logo GuYi](../assets/guyi-logo.png)

[简体中文](../README.md) · [English](README.en.md) · [Bahasa Indonesia](README.id.md) · [日本語](help/ja.md) · [한국어](help/ko.md)

**Berkomunikasi lintas bahasa tanpa meninggalkan kolom pengetikan.** GuYi adalah metode input (IME) native untuk Apple Silicon/macOS 26. Rime menangani Pinyin Mandarin secara lokal; API model AI pilihan Anda menampilkan terjemahan dekat kursor untuk dipilih, disalin, atau dibacakan. Teks yang dipilih di aplikasi lain juga dapat diterjemahkan di dekatnya. Kartu belajar opsional menjelaskan kosakata, IPA, tata bahasa dan contoh.

GuYi ditujukan bagi pelajar, tim lintas negara, staf dukungan, dan pengguna yang berkomunikasi lintas bahasa. Lima mode inputnya mencakup Pinyin Mandarin, Inggris, Indonesia, kana Jepang, dan Korea 2-Set; bahasa tujuan terjemahan diatur terpisah. Mode input pendek cocok untuk balasan harian; pintasan yang dapat diubah mengaktifkan komposisi kalimat penuh saat diperlukan.

> Kompatibilitas: Tetap sediakan metode input sistem. Di Chrome, Caps Lock beralih ke ABC sistem; gunakan “中 / EN” atau pintasan khusus agar tetap memakai GuYi. Seleksi lintas aplikasi dan latensi layanan cloud masih diuji.

## Manfaat praktis

| Kegiatan | Alur biasa | Dengan GuYi |
| --- | --- | --- |
| Membalas dalam bahasa lain | Menulis, membuka penerjemah, menyalin, menempel | Melihat dan memilih terjemahan di dekat kursor |
| Memahami pesan | Menyalin lalu berpindah aplikasi | Memilih teks dan melihat terjemahan di dekatnya |
| Mempelajari ungkapan | Mencari arti, pelafalan dan tata bahasa terpisah | Membuka kartu belajar dan mendengarkan |

Akurasi bergantung pada model dan konteks. Periksa hasil penting; terjemahan dan IPA berbantuan AI tidak dijamin lebih baik daripada alat bahasa khusus.

## Fitur

- Pinyin Rime lokal, input Latin Inggris dan Indonesia, romaji-ke-kana Jepang, Korea 2-Set, kandidat mendatar, pembelajaran frasa Mandarin, kandidat kata Inggris umum dan saran emoji dalam kelima mode input. Petunjuk Pinyin hanya tampil dalam mode Mandarin. Input Jepang mengubah romaji menjadi kana, tanpa kamus Kanji. Angka, desimal, pemisah ribuan, dan alamat web ditangani sesuai konteks.
- Pratinjau terjemahan dengan penyisipan eksplisit; mode pendek dan kalimat penuh. Empat belas bahasa tujuan yang dapat dipilih sendiri-sendiri, antarmuka Mandarin/Inggris/Indonesia/Jepang/Korea.
- Perhitungan tepat, misalnya `5/5=` → `1`; ekspresi salah atau melampaui batas tidak diberi hasil tebakan.
- Terjemahan teks terpilih dengan bahasa tujuan yang diingat, salin terjemahan, dengarkan teks asli/terjemahan, dan kartu “Pelajari cara menggunakannya”. Tautan, angka saja, serta kunci/ID yang tampak sensitif disaring.
- Pembacaan seleksi presisi opsional saat aplikasi tidak menyediakan teks terpilih melalui sistem: setelah seleksi atau Select All, GuYi menyalin sebentar lalu memulihkan papan klip. Aktif secara bawaan dan dapat dimatikan. Aplikasi riwayat papan klip tetap mungkin mencatat perubahan singkat ini. “Salin otomatis teks asli yang dipilih” adalah sakelar terpisah dan mati secara bawaan.
- Sepuluh slot teks/gambar/berkas yang dapat dipakai ulang dan cache terjemahan lokal memori/SQLite dengan batas. Akun layanan yang sama memakai ulang terjemahan saat model atau protokol API berganti; Segarkan memakai model saat ini dan mengganti hasil dalam cache.

## Instalasi

1. Unduh DMG untuk versi yang diperlukan dari tab **Releases** GitHub. Buka dan klik dua kali `GuYi-Input-Method.pkg`, lalu selesaikan lewat macOS Installer.
2. Di kolom teks, pilih GuYi dari menu input di bilah menu. Jika tidak muncul, ikuti [pemecahan masalah instalasi](help/id.md).
3. Untuk terjemahan AI, buka **GuYi Input Method** dari Applications, atur dan uji layanan model, lalu simpan. Input Pinyin tidak memerlukan API key.
4. Jika macOS memblokir pemasangan, lihat [pemecahan masalah instalasi](help/id.md).

Pembaruan biasa memakai jalur DMG → PKG yang sama dan mempertahankan pengaturan, kamus serta cache.

## Mengatur model AI

Di **Settings → Service**, pilih protokol API, isi URL dasar, ID model dan API key untuk penyedia tersebut. Uji koneksi, lalu simpan. Jika Codex atau Claude Code memiliki kunci API model yang jelas di Mac ini, **Impor konfigurasi API lokal** mengisi draf yang belum disimpan untuk diperiksa dan diuji; login langganan dan OAuth tidak diimpor.

| Protokol | Layanan yang sesuai | Contoh URL dasar |
| --- | --- | --- |
| Responses | OpenAI atau layanan dengan Responses API kompatibel | `https://api.openai.com/v1` |
| Chat Completions | Layanan dengan Chat Completions kompatibel OpenAI | URL dasar `/v1` dari penyedia |
| Claude / Anthropic Messages | Layanan yang mengimplementasikan Messages API | URL dasar dari dokumentasi penyedia |

“Kompatibel OpenAI” **tidak berarti hanya OpenAI**. Layanan lain dapat digunakan jika protokol dan autentikasi yang dipilih tersedia; tidak semua model yang mengaku kompatibel pasti berhasil. Jika gateway menolak output JSON Schema, aktifkan **Output kompatibel (GuYi memvalidasi JSON)** untuk layanan itu dan uji sebelum menyimpan. Cloud Volcengine Ark/Doubao dapat memakai rute Responses atau Chat Completions yang didukung dengan `https://ark.cn-beijing.volces.com/api/v3`, ID model atau endpoint `ep-` yang diaktifkan, dan API key Ark tersendiri. GuYi tidak membaca login aplikasi desktop Doubao. Beberapa layanan bernama dapat disimpan dengan protokol dan alamat yang sama; mengedit layanan yang ada hanya memperbarui entri tersebut. Langganan ChatGPT bukan saldo API.

Kunci disimpan sebagai berkas lokal **teks biasa** dengan izin khusus pengguna. Cache tidak dienkripsi. Input, seleksi dan pembelajaran mengirim teks terkait ke layanan pilihan Anda; gunakan HTTPS tepercaya. Jangan unggah kunci atau percakapan pribadi ke issue publik.

## Kontrol sehari-hari

| Tindakan | Bawaan |
| --- | --- |
| Kandidat Mandarin | Pinyin lalu Spasi atau `1–5`; `=`/`-` mengganti halaman saat menyusun Pinyin |
| Bahasa input | `Option+0` menggilir Mandarin, Inggris, Indonesia, Jepang, Korea; `Control+Option+J/K` langsung memilih Jepang/Korea |
| Bahasa utama/Inggris | Caps Lock pada aplikasi yang mendukung; `Control+Option+L` memberi fungsi GuYi yang sama dan dapat diubah. Pilihan awal mengikuti bahasa sistem Mandarin, Jepang, Korea atau Indonesia; pilihan tersimpan didahulukan. |
| Kalimat penuh | `Control+Option+Return` mengaktifkan/menonaktifkan |
| Sisipkan terjemahan | `Option+1/2/3` untuk Mandarin/Inggris/Indonesia; atur bahasa lain di Pintasan |
| Konten tersimpan | `Control+Option+angka` menyalin; tambah `Shift` untuk meminta tempel |
| Teks terpilih | Seret atau klik dua kali; `Command+A` pada editor yang didukung |

Pintasan fitur dapat diubah atau dimatikan di Pengaturan. Pratinjau tidak mengirim pesan; pembacaan suara tidak memasukkan teks.

Panduan lengkap: [Indeks panduan](使用说明.md) · [Bahasa Indonesia](help/id.md) · [English](help/en.md) · [中文](help/zh-Hans.md) · [日本語](help/ja.md) · [한국어](help/ko.md). Bantuan offline yang sama tersedia di aplikasi.

Lihat [catatan rilis](../CHANGELOG.md) untuk perubahan versi ini.

## Kode sumber dan lisensi

Dibuat dengan Swift, InputMethodKit, AppKit/SwiftUI, Rime dan SQLite. Build saat ini memerlukan Apple Silicon/macOS 26, toolchain Swift dan `librime` Homebrew. Direktori Vendor Rime adalah submodule dengan commit tetap: klon dengan `git clone --recurse-submodules`, atau jalankan `git submodule update --init --recursive` pada checkout yang sudah ada:

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
```

Kode milik GuYi menggunakan [Lisensi MIT](../LICENSE); dependensi dan kamus bawaan memiliki lisensi masing-masing di [pemberitahuan pihak ketiga](../THIRD_PARTY_NOTICES.md). Baca [kontribusi](../CONTRIBUTING.md) dan [keamanan](../SECURITY.md).
