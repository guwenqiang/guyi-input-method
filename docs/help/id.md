# Panduan GuYi Input Method

[简体中文](zh-Hans.md) · [English](en.md) · [Bahasa Indonesia](id.md)

## 1. Instalasi dan pembaruan

GuYi saat ini ditujukan untuk Apple Silicon/macOS 26. Unduh DMG stabil terbaru dari GitHub Releases, buka lalu klik dua kali `GuYi-Input-Method.pkg`. Selesaikan izin macOS Installer, kemudian buka GuYi Input Method dari Applications. Tambahkan melalui **System Settings → Keyboard → Text Input → Edit** dan pilih dalam kolom teks sesungguhnya. Tetap sediakan ABC sistem atau metode input lain.

Pembaruan memakai alur DMG → PKG yang sama dan biasanya mempertahankan pengaturan penyedia, kamus dan cache tanpa reboot. Pratinjau dengan tanda tangan pengembangan lokal ini belum memakai Developer ID atau notarisasi. Jangan menonaktifkan keamanan macOS bila aplikasi diblokir. Kompilasi, pemasangan dan registrasi tidak membuktikan GuYi bekerja di WeChat, Office atau aplikasi lain.

## 2. Mengatur layanan AI

Di **Settings → Service**, pilih protokol API, isi **URL dasar, ID model dan API key penyedia**, jalankan tes koneksi/terjemahan, lalu simpan. Daftar model hanya mencerminkan katalog penyedia; tidak semua model mendukung permintaan terjemahan terstruktur GuYi.

GuYi mendukung OpenAI Responses, Chat Completions kompatibel OpenAI dan Claude/Anthropic Messages. “Kompatibel OpenAI” **tidak terbatas pada perusahaan OpenAI**: penyedia lain dapat bekerja jika mengimplementasikan endpoint, autentikasi dan keluaran terstruktur yang diperlukan. Contoh URL dasar OpenAI Responses adalah `https://api.openai.com/v1`; untuk Chat Completions pihak ketiga isi URL dasar `/v1` dari penyedia. Jangan menambahkan jalur operasi seperti `/responses` dua kali.

Doubao/Volcengine Ark adalah **API cloud**, bukan login aplikasi desktop Doubao. Gunakan rute Responses atau Chat Completions yang didukung, `https://ark.cn-beijing.volces.com/api/v3`, ID model aktif atau endpoint `ep-`, serta API key Ark tersendiri. GuYi menyimpan konfigurasi terbaru tiap penyedia; menyimpan konfigurasi baru untuk penyedia yang sama menggantikan sebelumnya. Berpindah kolom tanpa menyimpan tidak mengganti layanan aktif. Langganan ChatGPT bukan API key atau saldo API.

Utamakan HTTPS tepercaya. HTTP tidak mengenkripsi kunci maupun teks asli. API key disimpan dalam berkas lokal **teks biasa** dengan izin khusus pengguna, bukan dienkripsi di Keychain. Terjemahan yang diaktifkan mengirim teks terkait ke penyedia pilihan Anda.

## 3. Pinyin, kandidat dan aritmetika tepat

Dalam mode Mandarin, ketik `nihao`, lalu pilih kandidat dengan Spasi atau `1–5`. Satu baris kandidat memuat 1–5 item sesuai lebarnya. Kiri/Kanan memindahkan pilihan; `=`/`-` berpindah halaman saat Pinyin sedang disusun. Page Up/Page Down dan klik juga tersedia. Frasa pribadi dipelajari secara lokal. Kata Inggris umum dan emoji seperti `haha` dapat muncul sebagai kandidat.

Tanpa komposisi aktif, spasi, angka dan tanda baca langsung dimasukkan. Titik desimal, titik dua waktu dan koma ribuan tetap literal, misalnya `1.2`, `09:30`, `3,444.50`; alamat web/email juga dipertahankan sesuai konteks. Saat Pinyin masih tertunda, Return dapat memasukkan huruf mentah tanpa baris baru. Tanpa komposisi, Return diserahkan ke aplikasi dan dapat mengirim pesan atau menjalankan perintah terminal.

Ketik `5/5=` secara berurutan pada kolom kosong atau setelah spasi. Panel hitung yang ringkas menampilkan hasil tepat `1`; Return atau klik baru memasukkan hasil tanpa baris baru. Mendukung aritmetika, kurung, desimal, pemisah ribuan dan pangkat bilangan bulat (`^`). Desimal berulang menjadi pecahan tepat. Ekspresi salah, pembagian nol dan overflow tidak diberi hasil tebakan. Batas 256 karakter dan 32 tingkat kurung.

## 4. Terjemahan saat mengetik dan mode kalimat

Panel terjemahan muncul dekat kursor. Teks asli dan bahasa tujuan aktif ditampilkan dalam baris terpisah; pilih terjemahan secara eksplisit untuk memasukkannya. Mode pendek adalah bawaan sehari-hari. `Control+Option+Return` mengaktifkan mode kalimat penuh untuk pesan panjang; teks panjang digulir di dalam panel. Dalam mode kalimat, Return pertama mengonfirmasi teks Inggris, Return berikutnya memasukkannya. Coba pada draf sebelum menekan Return dalam aplikasi chat.

Bawaan: `Option+0` menggilir bahasa teks asli; `Option+1/2/3` memilih hasil Mandarin/Inggris/Indonesia. Atur target lain di halaman Pintasan. Bila terjemahan belum siap, pintasan menampilkan pesan menunggu dan tidak jatuh ke simbol aplikasi. Semua pintasan fitur dapat diubah atau dimatikan. Tab/Shift+Tab tetap milik aplikasi; Esc membatalkan komposisi aktif.

Pengaturan macOS “Use the Caps Lock key to switch to and from ABC” dapat mengganti sumber input. Stabilitas lintas aplikasi masih diuji; sediakan metode input sistem sebagai cadangan. Mengetik huruf kapital di GuYi bukan berarti beralih ke ABC sistem.

## 5. Terjemahan seleksi dan suara

Seret atau klik dua kali teks bahasa alami untuk membuka panel terjemahan di dekat seleksi. Beberapa bahasa tujuan dapat dipilih dan diingat. Terjemahan otomatis untuk bahasa yang sama dilewati secara bawaan; campuran bahasa diterjemahkan sebagai satu teks penuh. Angka saja, rumus, tautan, kunci/ID yang jelas sensitif dan jalur berkas disaring. Klik di luar, mengetik atau berpindah aplikasi menutup pratinjau. Tombol pengeras suara pada teks asli atau terjemahan memulai pembacaan; klik lagi untuk berhenti. Suara tidak memasukkan teks. Baris terjemahan memiliki tombol Salin; baris asli tidak menduplikasi perintah Salin aplikasi.

Sebagian aplikasi khusus tidak menyediakan seleksi tepat melalui Accessibility macOS. **Pembacaan seleksi presisi** aktif secara bawaan: hanya setelah seretan, klik ganda atau `Command+A` yang didukung, dan hanya bila pembacaan sistem gagal, GuYi menyalin sebentar lalu memulihkan papan klip sebelumnya. Bila snapshot lengkap tidak dapat dipulihkan, proses dibatalkan tanpa menebak melalui OCR. **Aplikasi riwayat papan klip tetap mungkin mencatat perubahan sementara.** Matikan di Input dan Terjemahan bila tidak sesuai kebutuhan. “Salin otomatis teks asli yang dipilih” adalah sakelar lain, mati secara bawaan; bila dinyalakan, teks asli sengaja ditinggalkan di papan klip setelah pratinjau.

Nama berkas di dialog Simpan, kolom satu baris biasa, pencarian kontak dan kolom aman tidak memicu terjemahan seleksi otomatis. Teks bahasa alami pada badan dokumen, email dan chat dapat dipilih. Aplikasi memiliki implementasi berbeda; jika sistem maupun jalur kompatibilitas tidak memberi hasil tepat, GuYi tidak boleh menampilkan terjemahan yang belum pasti.

“Terjemahkan teks yang disalin” adalah sakelar tersendiri. Bila aktif, hanya salinan baru yang dilakukan secara jelas yang diproses, bukan isi papan klip lama atau tindakan tempel. Pengelola sandi, penanda papan klip terlindungi dan kredensial yang tampak sensitif tetap dikecualikan.

## 6. Pembelajaran, cache dan konten tersimpan

Tombol buku membuka “Pelajari cara menggunakannya” untuk IPA Inggris/Indonesia, kata kunci, tata bahasa, tingkat formalitas dan contoh sesuai kebutuhan. Penjelasan dibantu AI, bukan verifikasi kamus. Mengubah teks asli menghapus penjelasan lama. Pembacaan memakai suara macOS yang tersedia; suara pria/wanita alami tertentu tidak dijanjikan.

GuYi memeriksa cache memori dan SQLite terbatas sebelum memakai jaringan. Masa simpan bawaan tujuh hari, dapat menjadi 1–365 hari, dimatikan atau dibersihkan, dan hanya menyimpan terjemahan lengkap bagi bahasa tujuan aktif. Kosakata daring dapat diperbarui harian; kegagalan tetap memakai daftar lokal. Pembelajaran frasa Rime terpisah dari cache terjemahan.

**Tools → Konten Tersimpan** menyediakan sepuluh slot lokal untuk teks/gambar/berkas. `Control+Option+angka` menyalin; tambah `Shift` untuk meminta tempel. Teks multibaris dan lampiran pada terminal hanya disalin; GuYi tidak mengirim Return otomatis. Teks maksimal 64 KiB dan berkas maksimal 10 MiB. Slot tidak dienkripsi; jangan simpan sandi atau API key.

## 7. Privasi dan pemecahan masalah

Kredensial penyedia berada di `~/Library/Application Support/guyi/Configuration` sebagai berkas teks biasa dengan izin khusus pengguna. Kamus, cache dan konten tersimpan juga berada di direktori pengguna; pembaruan normal mempertahankannya. Cache tidak dienkripsi dan indeks sidik jari bukan jaminan anonim. Terjemahan/pembelajaran mengirim teks terkait ke penyedia menurut kebijakan datanya.

Untuk galat API: 401 biasanya kunci, 403 izin penyedia, 400 kompatibilitas protokol/model/keluaran terstruktur, 404 URL atau ID model, 429 kuota/batas laju, timeout jaringan atau layanan. Model yang muncul di daftar belum tentu dapat dipanggil. Terjemahan cloud lengkap masih bisa memerlukan beberapa detik; cache cepat bukan ukuran latensi jaringan. Laporkan versi GuYi/macOS/aplikasi dan langkah yang disamarkan, jangan kunci, sandi atau obrolan pribadi.

Tangkapan layar biasa dan panjang masih dikembangkan; menu, pintasan dan pengaturannya disembunyikan pada build ini. Pakai alat screenshot macOS. Untuk menghapus, ganti ke metode input lain, hapus GuYi dari daftar input sistem, lalu hapus `/Applications/GuYi输入法.app` dan `/Library/Input Methods/GuYi输入法.app`. Jangan hapus seluruh direktori Input Methods. Hapus data pribadi hanya bila memang dimaksudkan.
