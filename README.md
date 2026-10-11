# GuYi Input Method

![GuYi logo](assets/guyi-logo.png)

[简体中文](README.md) · [English](docs/README.en.md) · [Bahasa Indonesia](docs/README.id.md) · [日本語](docs/help/ja.md) · [한국어](docs/help/ko.md)

**在输入的位置完成跨语言表达。** GuYi 是 Apple Silicon/macOS 26 的原生输入法：本地 Rime 拼音负责中文输入，你配置的大模型服务提供多语言译文，译文在光标附近可选、可复制、可朗读。选中别处的文字也能翻译，无须在聊天应用和翻译网页间反复复制粘贴。

适合经常用中文、英文或印尼语沟通的学生、跨境团队、客服与技术人员。日常保留短输入节奏，需要组织完整消息时可切换整句模式。点击书本按钮还可按需查看 AI 辅助的词义、音标、语法与例句。

> 兼容性：建议保留系统输入法作后备。Chrome 中 Caps Lock 会切到系统 ABC；若要留在 GuYi，请使用“中 / EN”或自定义快捷键。部分应用的选区和云服务响应速度仍在持续验证。

## 为什么用 GuYi

| 任务 | 常见流程 | GuYi |
| --- | --- | --- |
| 回复另一种语言的消息 | 输入 → 翻译网页 → 复制译文 → 粘贴 | 在原输入框中查看并选择译文 |
| 理解收到的文本 | 复制 → 切应用 → 翻译 | 选中后在文字附近查看译文 |
| 学习一段表达 | 再查词典、发音和语法 | 在译文旁按需打开学习卡并朗读 |

翻译质量取决于你配置的模型、提示词与原文；AI 译文和音标需要复核，不宣称必然优于专用翻译服务。

## 功能

- 本地 Rime 拼音、英文与印尼语拉丁字母、日语罗马字转假名、韩语 2-Set、横排候选、中文个人组词学习、常见英文词候选与五种输入模式的表情联想；拼音提示仅在中文模式显示。数字、小数点、千分位、网址和常用标点按上下文输入。日语输入提供假名转换，不含汉字词典。
- 输入时的多语言预览和明确上屏；短输入与整句模式可切换。14 个目标语言独立开关，中、英、印尼、日、韩五种界面。
- 精确计算：例如 `5/5=` 显示 `1`，确认后插入；不确定或溢出时不猜测结果。
- 选中翻译支持目标语言多选、复制译文、朗读原文/译文及“读懂 · 学会用”。不翻译纯数字、链接和明显的密钥/标识符。
- 对不提供系统选区的应用，可选精确兼容读取：明确划词或全选后短暂复制、读取并恢复剪贴板。默认开启，但可关闭；剪贴板历史工具仍可能记录这次短暂变化。自动复制原文是另一个独立开关，默认关闭。
- 十个常用内容槽可保存文字、图片或文件；本地内存和 SQLite 译文缓存有容量/保留期限制。同一服务账号切换模型或接口协议仍复用译文；点刷新才用当前模型重新翻译并覆盖缓存。

## 安装

1. 从 GitHub **Releases** 下载所需版本的 DMG，打开后双击 `GuYi-Input-Method.pkg`，按 macOS Installer 提示完成安装。不要把旧 DMG 与新版本混用。
2. 在目标应用的输入框中，从菜单栏的输入法菜单选择 GuYi；若菜单里没有，请按[安装排障](docs/help/zh-Hans.md)检查。
3. 需要 AI 翻译时，从“应用程序”打开 GuYi 设置，按下文配置模型服务并保存。纯拼音输入不需要 API Key。
4. 如果安装时被 macOS 拦截，请按[使用帮助中的安装排障](docs/help/zh-Hans.md)处理。

升级使用同一 DMG → PKG 安装流程，正常保留本机设置、词库与缓存。

## 配置大模型

在设置的**服务**页选择接口协议，填写基础 API 地址、模型 ID 和该服务的 API Key，先用“测试连接”验证，再保存。若本机 Codex 或 Claude Code 已保存明确的模型 API Key，可用“载入本机 API 配置”填入草稿，再核对、测试和保存；订阅/OAuth 登录不会被导入。

| 接口协议 | 适用服务 | 地址示例 |
| --- | --- | --- |
| Responses | OpenAI 或实现兼容 Responses API 的服务 | `https://api.openai.com/v1` |
| Chat Completions | 实现 OpenAI 兼容 Chat Completions API 的服务 | 服务商提供的 `/v1` 基础地址 |
| Claude / Anthropic Messages | 实现 Messages API 的服务 | 服务商提供的基础地址 |

OpenAI 协议**不限于 OpenAI 公司**：任何实现相应接口和认证的服务都可尝试配置；“兼容”不保证所有模型都能调用。若中转服务拒绝 JSON Schema 输出格式，可为该服务开启“兼容输出（由 GuYi 校验 JSON）”，测试成功后保存。豆包/火山方舟云 API 可按其开放的 Responses 或 Chat Completions 接口填写基础地址 `https://ark.cn-beijing.volces.com/api/v3`、已开通的模型或 `ep-` 接入点 ID，以及单独的方舟 API Key。GuYi 不读取豆包桌面版登录。同协议、同地址也可新建多个命名服务；编辑已有服务只更新该项，其他服务保留。ChatGPT 订阅不等于 API Key 或 API 额度。

**隐私：**密钥存于当前用户的本机权限受限文件，仍是明文；译文缓存也未加密。输入翻译、选中翻译与学习请求会把相应文字发送到你配置的服务。请使用可信的 HTTPS 服务，不要在公开 issue 中贴密钥或私人聊天内容。

## 常用操作

| 操作 | 默认方式 |
| --- | --- |
| 中文候选 | 输入拼音，空格或数字 `1–5` 选词；`=`/`-` 在拼音候选中翻页 |
| 输入语言 | `Option+0` 循环中文、英文、印尼语、日语、韩语；`Control+Option+J/K` 直达日/韩 |
| 常用语言/英文 | Caps Lock 在支持的应用内切换；`Control+Option+L` 是可自定义的等效快捷键。首次配对语言随系统中文、日语、韩语或印尼语确定，已有保存选择优先 |
| 整句模式 | `Control+Option+Return` 开/关 |
| 插入译文 | `Option+1/2/3` 对应中文/英文/印尼语；其他语言可在快捷键页设置 |
| 常用内容 | `Control+Option+数字` 复制；加 `Shift` 请求粘贴 |
| 选中翻译 | 拖选、双击；支持的编辑框中可用 `Command+A` |

所有功能快捷键均可在设置中修改或禁用，若与宿主应用冲突请改用别的组合。选中预览不自动发送消息；原文与译文的朗读也不插入文字。

完整步骤和排障：[使用说明](docs/使用说明.md) · [中文帮助](docs/help/zh-Hans.md) · [English guide](docs/help/en.md) · [Panduan Indonesia](docs/help/id.md) · [日本語](docs/help/ja.md) · [한국어](docs/help/ko.md)。应用内提供同样的离线帮助。

版本变化见三语[更新说明](CHANGELOG.md)。

## 源码与许可

使用 Swift、InputMethodKit、AppKit/SwiftUI、Rime 和 SQLite。Apple Silicon/macOS 26、Swift 工具链与 Homebrew `librime` 是当前构建前提。三个 Rime Vendor 目录是固定提交的 submodule，克隆时需运行 `git clone --recurse-submodules`，已有检出运行 `git submodule update --init --recursive`：

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package.sh
```

项目自有代码按 [MIT License](LICENSE) 提供；Rime、词库与随包依赖保留各自许可证，详见 [第三方说明](THIRD_PARTY_NOTICES.md)。问题与贡献请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。
