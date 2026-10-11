# GuYi 版本更新 / Release Notes / Catatan Rilis

## 0.2.73

### 简体中文

- 在输入位置预览、复制或明确插入多语言译文；选中文字后可在附近翻译、朗读和查看“读懂 · 学会用”。
- 支持中文拼音、英文与印尼语拉丁字母、日语罗马字转假名和韩语 2-Set 输入；首次使用按系统语言确定常用语言/英文组合，增加可自定义的切换快捷键及日、韩界面和帮助。改进英文候选、表情联想、常用词组学习、数学计算与跨应用切换后的未确认拼音保留。
- 云服务支持 Responses、Chat Completions 和 Anthropic Messages。同协议可保存多个命名服务；对不接受 JSON Schema 的兼容接口可单独启用由 GuYi 校验的 JSON 输出。
- “读懂 · 学会用”可在唯一展开的英文或印尼语译文上自动生成学习内容；改进兼容接口的学习结果解析、面板滚动和锚点稳定性。Finder 双击文件不再误触发选中翻译。
- 同一服务账号的译文缓存跨模型和接口协议复用；点击刷新使用当前模型重新翻译并覆盖旧译文。改进常规升级与选区读取。
- 日语输入提供假名转换，不含汉字词典；部分应用的自绘文本控件可能无法提供精确选区。

### English

- Preview, copy or explicitly insert translations at the caret. Translate selected text nearby, listen to it, and open optional learning notes.
- Type with Chinese Pinyin, English and Indonesian Latin input, Japanese romaji-to-kana and Korean 2-Set. The first native/English pair follows the system language; a configurable shortcut offers the same toggle as Caps Lock in supported apps. Japanese and Korean interfaces and help are included. Improves common English candidates, emoji suggestions, learned phrases, arithmetic and unfinished Pinyin across app switches.
- Connect through Responses, Chat Completions or Anthropic Messages. Save multiple named services using the same protocol; enable GuYi-validated JSON output for compatible gateways that reject JSON Schema.
- Open learning notes automatically when only one English or Indonesian translation is expanded. Improve compatible-provider lesson parsing, popup scrolling and caret anchoring. Double-clicking a file in Finder no longer triggers selection translation.
- Reuse translation cache entries across models and API protocols on the same service account. Refresh translates with the current model and replaces the cached result. Improves routine upgrades and selection reading.
- Japanese input does not include a Kanji dictionary; some custom-rendered text controls cannot expose an exact selection.

### Bahasa Indonesia

- Pratinjau, salin, atau sisipkan terjemahan secara eksplisit di dekat kursor. Terjemahkan teks terpilih, dengarkan, dan buka catatan belajar bila diperlukan.
- Input Pinyin Mandarin, Latin Inggris dan Indonesia, romaji-ke-kana Jepang, dan Korea 2-Set. Pasangan bahasa utama/Inggris awal mengikuti bahasa sistem; pintasan yang dapat diubah memberi fungsi yang sama dengan Caps Lock pada aplikasi yang mendukung. Antarmuka dan panduan Jepang/Korea tersedia. Kandidat Inggris umum, saran emoji, pembelajaran frasa, perhitungan, dan Pinyin yang belum dikonfirmasi saat berpindah aplikasi telah diperbaiki.
- Hubungkan melalui Responses, Chat Completions, atau Anthropic Messages. Simpan beberapa layanan bernama dengan protokol sama; aktifkan output JSON yang diperiksa GuYi untuk gateway kompatibel yang menolak JSON Schema.
- Catatan belajar dibuat otomatis jika hanya satu terjemahan Inggris atau Indonesia yang terbuka. Pembacaan hasil belajar dari gateway kompatibel, pengguliran panel, dan posisi panel diperbaiki. Klik ganda berkas di Finder tidak lagi memicu terjemahan seleksi.
- Cache terjemahan dipakai ulang lintas model dan protokol API pada akun layanan yang sama. Segarkan menerjemahkan dengan model saat ini dan mengganti hasil lama. Peningkatan juga mencakup pembaruan aplikasi dan pembacaan seleksi.
- Input Jepang tidak memiliki kamus Kanji; beberapa kontrol teks khusus tidak menyediakan seleksi yang tepat.

### 日本語

- 入力位置で多言語の訳文を確認・コピー・明示的に挿入できます。選択したテキストは近くで翻訳でき、原文と訳文の読み上げや「読んで使う」学習表示にも対応します。
- 中国語ピンイン、英語・インドネシア語のラテン文字入力、日本語のローマ字から仮名への変換、韓国語の2ボル式入力に対応しました。システム言語に応じた初期入力言語の組み合わせと、変更可能な切替ショートカットを追加しました。英語候補、絵文字候補、学習した語句、計算、アプリ切替後の未確定入力も改善しています。
- Responses、Chat Completions、Anthropic Messages を利用できます。同じプロトコル・アドレスでも複数の名前付きサービスを保存でき、JSON Schema を拒否する互換サービスには GuYi が検証する JSON 出力を設定できます。
- 展開中の学習対象が英語またはインドネシア語の一つだけなら学習内容を自動表示します。互換サービスの学習結果の解析、パネルのスクロールと位置を改善し、Finder のファイルをダブルクリックしても選択翻訳を起動しないようにしました。
- 同じサービスアカウントではモデルや API プロトコルを切り替えても訳文キャッシュを再利用できます。手動更新では現在のモデルで再翻訳し、古いキャッシュを置き換えます。選択テキストの取得と通常のアップグレードも改善しました。
- 日本語入力は仮名変換に対応しますが、漢字辞書は含みません。一部の独自描画テキスト欄では正確な選択範囲を取得できない場合があります。

### 한국어

- 입력 위치에서 다국어 번역을 확인하고 복사하거나 명시적으로 삽입할 수 있습니다. 선택한 텍스트는 근처에서 번역하고 원문과 번역문을 읽어 주거나 학습 화면에서 살펴볼 수 있습니다.
- 중국어 병음, 영어·인도네시아어 라틴 문자, 일본어 로마자-가나 변환, 한국어 두벌식 입력을 지원합니다. 시스템 언어에 따른 초기 입력 언어 조합과 사용자 지정 전환 단축키를 추가했습니다. 영어 후보, 이모지 추천, 사용자 어구 학습, 계산 및 앱 전환 후 미확정 입력도 개선했습니다.
- Responses, Chat Completions, Anthropic Messages를 지원합니다. 같은 프로토콜과 주소에도 이름이 다른 서비스를 여러 개 저장할 수 있으며, JSON Schema를 거부하는 호환 서비스에는 GuYi가 검증하는 JSON 출력을 사용할 수 있습니다.
- 펼쳐진 학습 대상 번역이 영어 또는 인도네시아어 하나뿐이면 학습 내용을 자동으로 표시합니다. 호환 서비스의 학습 결과 처리, 패널 스크롤과 위치를 개선했고 Finder에서 파일을 두 번 클릭해도 선택 번역이 실행되지 않도록 했습니다.
- 같은 서비스 계정에서는 모델이나 API 프로토콜을 바꿔도 번역 캐시를 재사용합니다. 수동 새로고침은 현재 모델로 다시 번역해 이전 캐시를 교체합니다. 선택 텍스트 읽기와 일반 업그레이드 과정도 개선했습니다.
- 일본어 입력에는 가나 변환만 포함되며 한자 사전은 없습니다. 일부 자체 렌더링 텍스트 입력란은 정확한 선택 범위를 제공하지 않을 수 있습니다.
