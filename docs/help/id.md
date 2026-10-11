# Panduan GuYi Input Method

[简体中文](zh-Hans.md) · [English](en.md) · [Bahasa Indonesia](id.md) · [日本語](ja.md) · [한국어](ko.md)

## 1. Instalasi dan pembaruan

GuYi saat ini ditujukan untuk Apple Silicon/macOS 26. Unduh DMG untuk versi yang diperlukan dari GitHub Releases, buka lalu klik dua kali `GuYi-Input-Method.pkg`, lalu selesaikan izin macOS Installer. Pemasang akan mencoba mengaktifkan GuYi; pilih dari menu input di bilah menu saat kolom teks aktif. Jika GuYi tidak muncul, tambahkan melalui **System Settings → Keyboard → Text Input → Edit**. Untuk terjemahan AI, buka GuYi Input Method dari Applications dan atur layanan model; input Pinyin tidak memerlukan API key.

Pembaruan memakai alur DMG → PKG yang sama dan biasanya mempertahankan pengaturan penyedia, kamus dan cache. Jika macOS menyatakan pengembang tidak dapat diverifikasi saat pertama kali dibuka, pastikan berkas berasal dari repositori ini. Setelah mencoba membukanya, pilih **System Settings → Privacy & Security → Open Anyway** dan ikuti petunjuk untuk mengizinkan berkas ini saja.

## 2. Mengatur layanan AI

Di **Settings → Service**, pilih protokol API, isi **URL dasar, ID model dan API key penyedia**, uji koneksi, lalu simpan. Daftar model hanya mencerminkan katalog penyedia; tidak semua model mendukung permintaan terjemahan terstruktur GuYi.

Anda juga dapat memilih **Impor konfigurasi API lokal**. Hanya setelah diklik, GuYi membaca login API key serta alamat/model Responses yang dipilih di Codex, atau `ANTHROPIC_API_KEY`, alamat dan model dari `~/.claude/settings.json` milik Claude Code. Periksa alamat dan model setelah impor; alamat HTTP menampilkan peringatan koneksi tanpa enkripsi. Impor hanya mengubah formulir yang belum disimpan, tanpa permintaan jaringan atau mengganti layanan aktif sampai Anda menguji dan menyimpannya. Langganan ChatGPT/Claude dan login OAuth bukan kunci API model.

GuYi mendukung OpenAI Responses, Chat Completions kompatibel OpenAI dan Claude/Anthropic Messages. “Kompatibel OpenAI” **tidak terbatas pada perusahaan OpenAI**: penyedia lain dapat bekerja jika mengimplementasikan endpoint, autentikasi dan keluaran yang diperlukan. Contoh URL dasar OpenAI Responses adalah `https://api.openai.com/v1`; untuk Chat Completions pihak ketiga isi URL dasar `/v1` dari penyedia. Jangan menambahkan jalur operasi seperti `/responses` dua kali. Jika gateway menolak output JSON Schema, aktifkan **Output kompatibel (GuYi memvalidasi JSON)** untuk layanan tersebut, uji, lalu simpan. GuYi tetap memeriksa kelengkapan bidang terjemahan; mode ini tidak memperbaiki kunci yang tidak valid atau model yang belum tersedia.

Doubao/Volcengine Ark adalah **API cloud**, bukan login aplikasi desktop Doubao. Gunakan rute Responses atau Chat Completions yang didukung, `https://ark.cn-beijing.volces.com/api/v3`, ID model aktif atau endpoint `ep-`, serta API key Ark tersendiri. Untuk menambah layanan, klik **Baru**, isi nama, protokol, alamat, model dan key, uji lalu simpan. Beberapa layanan bernama dapat memakai protokol dan alamat yang sama, lalu dipilih melalui **Layanan tersimpan**. Mengedit layanan yang ada hanya memperbarui entri tersebut; profil lama mendapat nama bawaan yang dapat diedit. Berpindah kolom tanpa menyimpan tidak mengganti layanan aktif. Langganan ChatGPT bukan API key atau saldo API.

Utamakan HTTPS tepercaya. HTTP tidak mengenkripsi kunci maupun teks asli. API key disimpan dalam berkas lokal **teks biasa** dengan izin khusus pengguna, bukan dienkripsi di Keychain. Terjemahan yang diaktifkan mengirim teks terkait ke penyedia pilihan Anda.

## 3. Pinyin, kandidat dan aritmetika tepat

Dalam mode Mandarin, ketik `nihao`, lalu pilih kandidat dengan Spasi atau `1–5`. Satu baris kandidat memuat 1–5 item sesuai lebarnya. Kiri/Kanan memindahkan pilihan; `=`/`-` berpindah halaman saat Pinyin sedang disusun. Page Up/Page Down dan klik juga tersedia. GuYi mempelajari frasa yang dipilih berulang kali secara lokal; pilihan satu karakter yang berurutan dapat membentuk frasa setelah pemakaian berulang, sedangkan karakter tunggal tidak ditambahkan sebagai kandidat frasa. Saran emoji pilihan tersedia untuk input Mandarin, Inggris, Indonesia, romaji Jepang, dan Korea; emoji hanya dimasukkan setelah dipilih. Petunjuk Pinyin hanya tampil dalam mode Mandarin.

Tanpa komposisi aktif, spasi, angka dan tanda baca langsung dimasukkan. Titik desimal, titik dua waktu dan koma ribuan tetap literal, misalnya `1.2`, `09:30`, `3,444.50`; alamat web/email juga dipertahankan sesuai konteks. Saat Pinyin masih tertunda, Return dapat memasukkan huruf mentah tanpa baris baru. Tanpa komposisi, Return diserahkan ke aplikasi dan dapat mengirim pesan atau menjalankan perintah terminal.

Ketik `5/5=` secara berurutan pada kolom kosong atau setelah spasi. Panel hitung yang ringkas menampilkan hasil tepat `1`; Return atau klik baru memasukkan hasil tanpa baris baru. Mendukung aritmetika, kurung, desimal, pemisah ribuan dan pangkat bilangan bulat (`^`). Desimal berulang menjadi pecahan tepat. Ekspresi salah, pembagian nol dan overflow tidak diberi hasil tebakan. Batas 256 karakter dan 32 tingkat kurung.

## 4. Terjemahan saat mengetik dan mode kalimat

Panel terjemahan muncul dekat kursor. Teks asli dan bahasa tujuan aktif ditampilkan dalam baris terpisah; pilih terjemahan secara eksplisit untuk memasukkannya. `Control+Option+Return` mengaktifkan mode kalimat; teks panjang digulir di dalam panel. Klik judul bahasa untuk melipat terjemahannya. Kandidat input dan terjemahan teks terpilih mengingat lipatannya secara terpisah, dan bahasa yang terlipat tidak diminta ke model. Bahasa yang dimatikan di Pengaturan tidak ditampilkan. Emoji tetap tersedia melalui kandidat Pinyin, menu input, atau pintasan yang dapat diubah. Dalam mode kalimat Mandarin, Return pertama menaruh Pinyin mentah seperti `guyi` ke draf sumber GuYi; Return kedua memasukkan kalimat. Jika kandidat Mandarin sudah dipilih, satu Return cukup. Mode kalimat Inggris juga memakai satu Return. Tidak ada baris baru. Mode frasa tetap memasukkan Pinyin mentah dengan satu Return. Coba pada draf sebelum menekan Return dalam aplikasi chat.

Bawaan: `Option+0` menggilir input Pinyin Mandarin, Inggris, Latin Indonesia, romaji Jepang, dan Korea 2-Set; `Control+Option+J/K` langsung memilih Jepang/Korea. Input Jepang saat ini mengubah romaji menjadi kana tanpa kamus Kanji. Mode input terpisah dari bahasa tujuan terjemahan. `Option+1/2/3` memilih hasil Mandarin/Inggris/Indonesia. Atur target lain di halaman Pintasan. Bila terjemahan belum siap, pintasan menampilkan pesan menunggu dan tidak jatuh ke simbol aplikasi. Semua pintasan fitur dapat diubah atau dimatikan. Tab/Shift+Tab tetap milik aplikasi; Esc membatalkan komposisi aktif.

Pada penggunaan pertama, sistem Mandarin, Jepang, Korea, atau Indonesia memasangkan bahasa tersebut dengan Inggris; sistem lain memakai Mandarin/Inggris. Pilihan input yang tersimpan tetap didahulukan. Di aplikasi yang mendukungnya, Caps Lock berganti antara Inggris dan mode GuYi non-Inggris terakhir. `Control+Option+L` melakukan hal yang sama dan dapat diubah atau dimatikan di Pintasan. GuYi tidak mengubah pengaturan Caps Lock sistem. Di Chrome, Caps Lock mungkin beralih ke ABC sistem. Agar tetap memakai GuYi, gunakan tombol bahasa input atau pintasan. Komposisi tertunda tetap di draf sumber tanpa dimasukkan lebih awal. Huruf Inggris bawaan tetap kecil; gunakan Shift+huruf untuk kapital. Sediakan input sistem sebagai cadangan.

## 5. Terjemahan seleksi dan suara

Saat aplikasi lain mengaktifkan Secure Keyboard Entry di macOS, input lokal GuYi tetap berfungsi pada kolom teks biasa; pemberitahuan bergambar kunci muncul di bagian atas panel kandidat. Terjemahan cloud, pembacaan teks terpilih dan papan klip, serta pembelajaran frasa pribadi dijeda selama mode ini aktif, lalu kembali sesuai pengaturan Anda.

Saat menyalin banyak teks tanpa perlu terjemahan, tekan `Control+Option+T` untuk menjeda terjemahan otomatis dari pilihan dan papan klip; tekan lagi untuk melanjutkan. Pintasan ini dapat diubah, dan pengalihan yang sama tersedia di menu GuYi serta Pengaturan Input dan Terjemahan. Jeda tidak mengubah pengaturan sakelar semula.

Seret atau klik dua kali teks bahasa alami untuk membuka panel terjemahan di dekat seleksi. Beberapa bahasa tujuan dapat dipilih dan diingat. Terjemahan otomatis untuk bahasa yang sama dilewati secara bawaan; campuran bahasa diterjemahkan sebagai satu teks penuh. Angka saja, rumus, tautan, kunci/ID yang jelas sensitif dan jalur berkas disaring. Klik di luar, mengetik atau berpindah aplikasi menutup pratinjau. Tombol pengeras suara pada teks asli atau terjemahan memulai pembacaan; klik lagi untuk berhenti. Suara tidak memasukkan teks. Baris terjemahan memiliki tombol Salin; baris asli tidak menduplikasi perintah Salin aplikasi.

Sebagian aplikasi khusus tidak menyediakan seleksi tepat melalui Accessibility macOS. **Pembacaan seleksi presisi** aktif secara bawaan: hanya setelah seretan, klik ganda atau `Command+A` yang didukung, dan hanya bila pembacaan sistem gagal, GuYi menyalin sebentar lalu memulihkan papan klip sebelumnya. Bila snapshot lengkap tidak dapat dipulihkan, proses dibatalkan tanpa menebak melalui OCR. **Aplikasi riwayat papan klip tetap mungkin mencatat perubahan sementara.** Matikan di Input dan Terjemahan bila tidak sesuai kebutuhan. “Salin otomatis teks asli yang dipilih” adalah sakelar lain, mati secara bawaan; bila dinyalakan, teks asli sengaja ditinggalkan di papan klip setelah pratinjau.

Nama berkas di dialog Simpan, kolom satu baris biasa, pencarian kontak dan kolom aman tidak memicu terjemahan seleksi otomatis. Teks bahasa alami pada badan dokumen, email dan chat dapat dipilih. Aplikasi memiliki implementasi berbeda; jika sistem maupun jalur kompatibilitas tidak memberi hasil tepat, GuYi tidak boleh menampilkan terjemahan yang belum pasti.

“Terjemahkan teks yang disalin” adalah sakelar tersendiri. Bila aktif, hanya salinan baru yang dilakukan secara jelas yang diproses, bukan isi papan klip lama atau tindakan tempel. Pengelola sandi, penanda papan klip terlindungi dan kredensial yang tampak sensitif tetap dikecualikan.

## 6. Pembelajaran, cache dan konten tersimpan

Tombol buku membuka “Pelajari cara menggunakannya” untuk IPA Inggris/Indonesia, kata kunci, tata bahasa, tingkat formalitas dan contoh sesuai kebutuhan. Penjelasan dibantu AI, bukan verifikasi kamus. Mengubah teks asli menghapus penjelasan lama. Pembacaan memakai suara macOS yang tersedia; suara pria/wanita alami tertentu tidak dijanjikan.

GuYi memeriksa cache memori dan SQLite terbatas sebelum memakai jaringan. Masa simpan bawaan tujuh hari, dapat menjadi 1–365 hari, dimatikan atau dibersihkan, dan hanya menyimpan terjemahan lengkap bagi bahasa tujuan aktif. Pergantian model atau protokol API memakai ulang terjemahan untuk akun layanan, teks sumber, dan pengaturan terjemahan yang sama. Tombol segarkan memakai model saat ini dan mengganti terjemahan dalam cache. Alamat API atau kunci yang berbeda tidak berbagi cache. Kosakata daring dapat diperbarui harian; kegagalan tetap memakai daftar lokal. Pembelajaran frasa Rime terpisah dari cache terjemahan.

**Tools → Konten Tersimpan** menyediakan sepuluh slot lokal untuk teks/gambar/berkas. `Control+Option+angka` menyalin; tambah `Shift` untuk meminta tempel. Teks multibaris dan lampiran pada terminal hanya disalin; GuYi tidak mengirim Return otomatis. Teks maksimal 64 KiB dan berkas maksimal 10 MiB. Slot tidak dienkripsi; jangan simpan sandi atau API key.

## 7. Privasi dan pemecahan masalah

Kredensial penyedia berada di `~/Library/Application Support/guyi/Configuration` sebagai berkas teks biasa dengan izin khusus pengguna. Kamus, cache dan konten tersimpan juga berada di direktori pengguna; pembaruan normal mempertahankannya. Cache tidak dienkripsi dan indeks sidik jari bukan jaminan anonim. Terjemahan/pembelajaran mengirim teks terkait ke penyedia menurut kebijakan datanya.

Untuk galat API: 401 biasanya kunci, 403 izin penyedia, 400 kompatibilitas protokol/model/keluaran terstruktur, 404 URL atau ID model, 429 kuota/batas laju, timeout jaringan atau layanan. Model yang muncul di daftar belum tentu dapat dipanggil. Terjemahan cloud lengkap masih bisa memerlukan beberapa detik; cache cepat bukan ukuran latensi jaringan. Laporkan versi GuYi/macOS/aplikasi dan langkah yang disamarkan, jangan kunci, sandi atau obrolan pribadi.

Untuk menghapus, ganti ke metode input lain, hapus GuYi dari daftar input sistem, lalu hapus `/Applications/GuYi输入法.app` dan `/Library/Input Methods/GuYi输入法.app`. Jangan hapus seluruh direktori Input Methods. Hapus data pribadi hanya bila memang dimaksudkan.
