import SwiftUI
import GuyiCore

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject private var serviceProfiles = ServiceProfiles.shared
    @ObservedObject private var hotwords = HotwordStore.shared
    @ObservedObject private var interfaceLanguage = InterfaceLanguage.shared
    @State private var section = "cloud"
    @State private var providerDrafts: ProviderDrafts
    @State private var draft: TranslationSettings
    @State private var key: String
    @State private var message = ""
    @State private var testing = false
    @State private var saving = false
    @State private var testTask: Task<Void, Never>?
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var providerRevision = 0
    @State private var clearingCache = false
    @State private var showingQuickContent = false

    init(preferences: Preferences) {
        self.preferences = preferences
        _draft = State(initialValue: preferences.settings)
        _key = State(initialValue: preferences.apiKey)
        _providerDrafts = State(initialValue: ProviderDrafts(settings: preferences.settings, key: preferences.apiKey))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("设置分类", selection: $section) {
                Text("服务").tag("cloud")
                Text("输入与翻译").tag("input")
                Text("外观").tag("appearance")
                Text("工具").tag("tools")
                Text("快捷键").tag("shortcuts")
                Text("通用").tag("general")
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
            Form {
                if section == "shortcuts" {
                    Section("快捷键") {
                        ForEach(InputShortcuts.actions, id: \.self) { action in
                            HStack {
                                Toggle(Localizer.text(InputShortcuts.title(action)), isOn: Binding(get: {
                                    InputShortcuts.binding(action, settings: draft).enabled
                                }, set: { value in
                                    var binding = InputShortcuts.binding(action, settings: draft)
                                    binding.enabled = value; setShortcut(action, binding)
                                }))
                                Spacer()
                                ShortcutRecorder(key: Binding(get: { InputShortcuts.binding(action, settings: draft).key }, set: { key in
                                    var binding = InputShortcuts.binding(action, settings: draft); binding.key = key; setShortcut(action, binding)
                                }), modifiers: Binding(get: { InputShortcuts.binding(action, settings: draft).modifiers }, set: { modifiers in
                                    var binding = InputShortcuts.binding(action, settings: draft); binding.modifiers = modifiers; setShortcut(action, binding)
                                }), allowsPlainKey: ["previousCandidates", "nextCandidates"].contains(action))
                                    .frame(width: 140, height: 26)
                                    .disabled(!InputShortcuts.binding(action, settings: draft).enabled)
                            }
                        }
                        Button("恢复默认快捷键") { draft.inputShortcuts = nil }
                        if !InputShortcuts.conflicts(settings: draft).isEmpty {
                            Text("快捷键存在重复，请调整后保存。").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if section == "appearance" {
                Section("界面") {
                    Picker("界面语言", selection: $interfaceLanguage.preference) {
                        Text("跟随系统").tag("system")
                        Text(verbatim: "简体中文").tag("zh-Hans")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Bahasa Indonesia").tag("id")
                    }
                    Picker("候选框主题", selection: Binding(get: { draft.candidateTheme ?? "dark" }, set: { draft.candidateTheme = $0 })) {
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                        Text("自定义").tag("custom")
                    }.pickerStyle(.segmented)
                    if draft.candidateTheme == "custom" {
                        ColorPicker("背景色", selection: Binding(get: { Color(nsColor: CandidateTheme.color(draft.candidateBackgroundHex ?? "1C1C1C") ?? .darkGray) }, set: { draft.candidateBackgroundHex = CandidateTheme.hex($0) }), supportsOpacity: false)
                        ColorPicker("强调色", selection: Binding(get: { Color(nsColor: CandidateTheme.color(draft.candidateAccentHex ?? "087BFF") ?? .systemBlue) }, set: { draft.candidateAccentHex = CandidateTheme.hex($0) }), supportsOpacity: false)
                    }
                    HStack {
                        Text("你好").padding(7).background(CandidateTheme(settings: draft).accent, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(CandidateTheme(settings: draft).selectedText)
                        Text("您好"); Spacer(); Text("Hello").foregroundStyle(.secondary)
                    }.padding(10).background(CandidateTheme(settings: draft).background, in: RoundedRectangle(cornerRadius: 9))
                        .environment(\.colorScheme, CandidateTheme(settings: draft).dark ? .dark : .light)
                    Button("恢复默认主题") { draft.candidateTheme = "dark"; draft.candidateBackgroundHex = nil; draft.candidateAccentHex = nil }
                }
                }
                if section == "tools" {
                Section("常用内容") {
                    Button("打开常用内容") { showingQuickContent = true }
                    Text("保存固定话术、图片和文件；快捷复制或请求粘贴。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                if section == "cloud" {
                Section("云端接口") {
                    if !serviceProfiles.saved.profiles.isEmpty {
                        Picker("已配置服务", selection: Binding(get: { ServiceProfile.identity(endpoint: draft.endpoint) }, set: { id in
                            guard let profile = serviceProfiles.saved.profiles.first(where: { $0.id == id }) else { return }
                            setProvider(profile.applying(to: draft))
                        })) {
                            if !serviceProfiles.saved.profiles.contains(where: { $0.id == ServiceProfile.identity(endpoint: draft.endpoint) }) {
                                Text("当前服务").tag(ServiceProfile.identity(endpoint: draft.endpoint))
                            }
                            ForEach(serviceProfiles.saved.profiles) { profile in Text(profile.title).tag(profile.id) }
                        }
                    }
                    Picker("接口协议", selection: Binding(get: { draft.effectiveAPIProtocol }, set: { setProvider(providerDrafts.switchingProtocol(to: $0, from: currentProvider)) })) {
                        Text(verbatim: "Responses").tag(CloudAPIProtocol.responses)
                        Text(verbatim: "Claude / Anthropic Messages").tag(CloudAPIProtocol.anthropic)
                        Text(Localizer.text("Chat Completions（通用兼容接口）")).tag(CloudAPIProtocol.chatCompletions)
                    }
                    Text("按接口协议接入服务；豆包 / 火山方舟可使用 Responses 或 Chat Completions。")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("API Key", text: $key)
                        .help("API Key 仅保存在本机配置中。")
                    if !preferences.keyStatus.isEmpty { Text(Localizer.text(preferences.keyStatus)).font(.caption).foregroundStyle(.secondary) }
                    TextField("API 地址", text: Binding(get: { draft.endpoint }, set: { setProvider(providerDrafts.switchingEndpoint(to: $0, from: currentProvider)) }))
                    if URL(string: draft.endpoint)?.host?.hasSuffix("volces.com") == true {
                        Text("火山方舟基础地址示例：https://ark.cn-beijing.volces.com/api/v3")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if URL(string: draft.endpoint)?.scheme?.lowercased() == "http" {
                        Text("当前使用 HTTP，连接未加密。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    TextField("模型 ID", text: $draft.model)
                        .help("豆包 / 火山方舟可填写已开通的模型 ID 或 ep- 开头的推理接入点 ID。")
                    Button(Localizer.text(loadingModels ? "读取中…" : "读取服务可用模型")) {
                        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            message = Localizer.text("请填写此服务的 API Key。")
                            return
                        }
                        loadingModels = true
                        let revision = providerRevision
                        let settings = draft
                        let credential = key
                        Task { @MainActor in
                            defer { if providerRevision == revision { loadingModels = false } }
                            do {
                                let found = try await ModelCatalog.fetch(settings: settings, apiKey: credential)
                                guard revision == providerRevision else { return }
                                models = found
                                message = models.isEmpty ? "服务未返回模型列表" : "已读取模型列表；选择后请测试翻译。"
                            } catch { if revision == providerRevision { message = error.localizedDescription } }
                        }
                    }.disabled(loadingModels)
                    if !models.isEmpty {
                        Picker("服务模型", selection: $draft.model) {
                            if !models.contains(draft.model) { Text(draft.model).tag(draft.model) }
                            ForEach(models, id: \.self) { Text(Localizer.text($0)).tag($0) }
                        }
                    }
                }
                }
                if section == "input" {
                Section("输入与翻译") {
                    Toggle("显示拼音提示", isOn: Binding(get: { draft.showPinyin == true }, set: { draft.showPinyin = $0 }))
                    Toggle("拼音联想表情", isOn: Binding(get: { draft.emojiCandidates != false }, set: { draft.emojiCandidates = $0 }))
                    Text("Return 原样输入拼音或英文 · 空格选择中文")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("网络词库 · 每日更新", isOn: Binding(get: { draft.hotwordsEnabled != false }, set: { draft.hotwordsEnabled = $0 }))
                    HStack {
                        Text(Localizer.text(hotwords.status)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("立即更新") { hotwords.check(force: true) }.disabled(hotwords.updating || preferences.settings.hotwordsEnabled == false)
                    }
                    Toggle("选中文本后翻译", isOn: Binding(get: { draft.translateSelection != false }, set: { draft.translateSelection = $0 }))
                    if draft.translateSelection != false {
                        Toggle("选中时自动复制原文", isOn: Binding(get: { draft.copySelectionAutomatically == true }, set: { draft.copySelectionAutomatically = $0 }))
                        Text("默认不改动剪贴板；复制译文需点击对应按钮。").font(.caption).foregroundStyle(.secondary)
                        Toggle("精确选区兼容读取", isOn: Binding(get: { draft.preciseSelectionCompatibility != false }, set: { draft.preciseSelectionCompatibility = $0 }))
                        Text("应用未提供系统选区时，短暂复制读取并恢复原剪贴板；剪贴板历史应用可能记录这次变化。")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("同语种不自动翻译", isOn: Binding(get: { draft.skipSameLanguageSelection != false }, set: { draft.skipSameLanguageSelection = $0 }))
                        if draft.skipSameLanguageSelection != false {
                            Picker("熟悉的语言", selection: Binding(get: { draft.selectionFamiliarLanguage ?? "system" }, set: { draft.selectionFamiliarLanguage = $0 == "system" ? nil : $0 })) {
                                Text("跟随界面语言").tag("system")
                                ForEach(Language.targets) { language in Text(language.title).tag(language.rawValue) }
                            }
                        }
                        Text("纯数字、符号和表情不自动翻译；混合语言触发后翻译完整选文。").font(.caption).foregroundStyle(.secondary)
                        if !AXIsProcessTrusted() {
                            Button("允许跨应用读取选中文本…") {
                                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                            }
                            Text("仅读取选中的文字；网页和聊天记录划词需要辅助功能权限。").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选中翻译的目标语言（可多选）").font(.caption).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                                ForEach(Language.targets) { language in
                                    Toggle(Localizer.text(language.title), isOn: Binding(get: {
                                        (draft.selectionLanguages ?? [.en, .id]).contains(language)
                                    }, set: { enabled in
                                        var selected = draft.selectionLanguages ?? [.en, .id]
                                        selected.removeAll { $0 == language }
                                        if enabled { selected.append(language) }
                                        draft.selectionLanguages = Language.targets.filter { selected.contains($0) }
                                    })).toggleStyle(.checkbox)
                                }
                            }
                            if draft.selectionLanguages?.isEmpty == true {
                                Text("未选择目标语言，不会发送翻译请求。").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                    Toggle("复制文本后翻译", isOn: Binding(get: { draft.translateClipboard != false }, set: { draft.translateClipboard = $0 }))
                    ForEach(Language.targets) { language in
                        Toggle(Localizer.format("开启%@译文", Localizer.text(language.title)), isOn: Binding(get: {
                            (draft.enabledLanguages ?? [.zh, .en, .id]).contains(language)
                        }, set: { enabled in
                            var languages = draft.enabledLanguages ?? [.zh, .en, .id]
                            languages.removeAll { $0 == language }
                            if enabled { languages.append(language) }
                            draft.enabledLanguages = languages
                        }))
                    }
                    Toggle("整句翻译模式", isOn: Binding(get: { draft.sentenceComposition == true }, set: { draft.sentenceComposition = $0 }))
                        .help("空格先选词；没有待转换拼音时，再按空格提交整句原文。输入时预览翻译，译文需明确选择后提交。")
                    Toggle("学习常用词与组词习惯（仅保存在本机用户词库）", isOn: $draft.learnInput)
                    Picker("原文语言", selection: $draft.source) {
                        ForEach(Language.allCases) { Text(Localizer.text($0.title)).tag($0) }
                    }
                    Picker("语气", selection: $draft.tone) {
                        ForEach(["忠实自然，保留原文语气", "商务专业，但不添加信息", "日常口语，自然简洁"], id: \.self) { Text(Localizer.text($0)).tag($0) }
                    }
                    Toggle("输入过程中自动翻译（将当前候选发送至配置的服务）", isOn: $draft.automatic)
                    HStack {
                        Text("触发延迟 \(draft.debounceMilliseconds) ms")
                        Slider(value: Binding(get: { Double(draft.debounceMilliseconds) }, set: { draft.debounceMilliseconds = Int($0) }), in: 0...1500, step: 20)
                    }
                    Picker("请求超时", selection: $draft.timeoutSeconds) {
                        Text("10 秒").tag(10.0)
                        Text("20 秒").tag(20.0)
                        Text("40 秒").tag(40.0)
                    }
                }
                }
                if section == "general" {
                Section("译文缓存") {
                    Toggle("保存本地译文缓存", isOn: Binding(get: { draft.effectiveCacheDays > 0 }, set: { draft.translationCacheDays = $0 ? 7 : 0 }))
                    if draft.effectiveCacheDays > 0 {
                        HStack {
                            Text("保留天数")
                            TextField("", value: Binding(get: { max(1, draft.effectiveCacheDays) }, set: { draft.translationCacheDays = max(1, min(365, $0)) }), format: .number)
                                .frame(width: 60)
                            Button("7 天") { draft.translationCacheDays = 7 }
                            Button("15 天") { draft.translationCacheDays = 15 }
                            Button("30 天") { draft.translationCacheDays = 30 }
                        }
                    }
                    Text("只缓存开启语言。内存最多 8 MiB／1,024 条；数据库最多 128 MiB／10,000 条。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(Localizer.text(clearingCache ? "清除中…" : "清除译文缓存")) {
                        clearingCache = true
                        TranslationCache.shared.clear()
                        Task { @MainActor in
                            await TranslationCache.shared.flush()
                            clearingCache = false
                            message = "译文缓存已清除"
                        }
                    }.disabled(clearingCache)
                }
                }
                if section == "input" {
                Section("术语表 · 每行一组对应关系") {
                    TextEditor(text: $draft.glossary).font(.system(.body, design: .monospaced)).frame(height: 70)
                    Text("例如：授信额度 = credit limit = limit kredit。术语表会随翻译请求发送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                if section == "general" {
                Section("权限与隐私") {
                    if !TerminalCapsLockSwitch.hardwareAccessGranted {
                        Button("允许 Caps Lock 中英文切换…") { TerminalCapsLockSwitch.shared.requestHardwareAccess() }
                        Text("仅接收 Caps Lock 键，不接收其他键的内容。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("用户词库不上传。开启译文缓存后，译文会保存到本机数据库，可定期过期或手动清除；它不是加密保险箱。")
                        .font(.caption)
                }
                }
            }.formStyle(.grouped)
                .onReceive(NotificationCenter.default.publisher(for: .guyiSentenceModeChanged)) { _ in
                    draft.sentenceComposition = preferences.settings.sentenceComposition
                }
            if !message.isEmpty { Text(Localizer.text(message)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(4) }
            Divider()
            HStack {
                if section == "cloud" {
                    Button(Localizer.text(testing ? "测试中…" : "测试连接")) { test() }.disabled(testing)
                }
                Spacer()
                Text(Brand.version).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button(Localizer.text(saving ? "保存中…" : "保存设置")) {
                    guard InputShortcuts.conflicts(settings: draft).isEmpty else { message = Localizer.text("快捷键存在重复，请调整后保存。"); return }
                    testTask?.cancel()
                    testing = false
                    saving = true
                    Task { @MainActor in
                        do { try await preferences.save(draft, key: key); message = "已保存，重启后仍然有效。" }
                        catch { message = error.localizedDescription }
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).disabled(saving)
            }
        }.padding(16).frame(width: 660, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, interfaceLanguage.locale)
        .sheet(isPresented: $showingQuickContent) {
            VStack {
                QuickContentView()
                Button(Localizer.text("关闭")) { showingQuickContent = false }.padding(.bottom, 16)
            }
        }
        .task {
            if !serviceProfiles.saved.profiles.contains(where: { $0.id == ServiceProfile.identity(endpoint: preferences.settings.endpoint) }) {
                do { try await serviceProfiles.remember(settings: preferences.settings, key: preferences.apiKey) }
                catch { message = "服务配置未能保存到本机，请检查配置目录权限。" }
            }
        }
        .onDisappear { testTask?.cancel(); rememberServiceDraft() }
        .onReceive(NotificationCenter.default.publisher(for: .guyiSettingsChanged)) { _ in
            if saving { draft = preferences.settings; providerDrafts.remember(currentProvider) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .guyiSelectionLanguagesChanged)) { _ in
            draft.selectionLanguages = preferences.settings.selectionLanguages
        }
    }
    private func test() {
        testing = true
        message = "正在用当前表单配置翻译测试句，将产生少量 API 用量…"
        var settings = draft
        settings.source = draft.source == .auto ? .zh : draft.source
        if settings.translationTargets.isEmpty {
            message = Localizer.text("请先开启至少一种译文语言。")
            testing = false
            return
        }
        let apiKey = key
        let samples: [Language: String] = [.zh: "请明天下午三点前确认订单。", .en: "Please confirm the order by 3 p.m. tomorrow.", .id: "Mohon konfirmasi pesanan sebelum pukul tiga sore besok."]
        testTask = Task { @MainActor in
            let start = Date()
            do {
                let translated = try await OpenAITranslator().stream(samples[settings.source] ?? "GuYi 2026", settings: settings, apiKey: apiKey) { _ in }
                try Task.checkCancellation()
                let values = settings.translationTargets.map { $0.title + ": " + translated.text(for: $0) }.joined(separator: "\n")
                message = Localizer.format("连接成功 · %.2f 秒", Date().timeIntervalSince(start)) + "\n" + values
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            testing = false
        }
    }
    private var currentProvider: ProviderDrafts.Form { .init(settings: draft, key: key) }
    private func setShortcut(_ action: String, _ binding: InputShortcut) {
        var bindings = draft.inputShortcuts ?? [:]
        bindings[action] = binding
        draft.inputShortcuts = bindings
    }
    private func rememberServiceDraft() {
        let settings = draft, credential = key
        Task { @MainActor in
            do { try await serviceProfiles.remember(settings: settings, key: credential) }
            catch { message = "服务配置未能保存到本机，请检查配置目录权限。" }
        }
    }
    private func setProvider(_ form: ProviderDrafts.Form) {
        rememberServiceDraft()
        providerRevision += 1
        loadingModels = false
        testTask?.cancel()
        testing = false
        draft.endpoint = form.settings.endpoint
        draft.apiProtocol = form.settings.apiProtocol
        draft.model = form.settings.model
        key = form.key
        models = []
        message = ""
    }
}
