# 第三方来源与许可

仓库根目录的 MIT 许可证仅覆盖 GuYi 项目自有代码；下列组件与数据保留其原许可证、版权和通知。打包脚本会把实际分发依赖的许可材料放入应用的 `Resources/Licenses`。新增或升级依赖时必须重新核对许可证及二进制分发义务。

| 组件 | 来源 | 说明 |
| --- | --- | --- |
| librime | https://github.com/rime/librime | BSD-3-Clause；构建时来自 Homebrew，随包保留对应通知 |
| luna-pinyin | https://github.com/rime/rime-luna-pinyin | LGPL-3.0；保留 Vendor 下 LICENSE、AUTHORS、原词典 |
| essay | https://github.com/rime/rime-essay | LGPL-3.0；保留 Vendor 下 LICENSE、AUTHORS、原语料 |
| prelude | https://github.com/rime/rime-prelude | 开发时参考，不是当前方案必需运行资源 |
| rime-jaroomaji 罗马字方案及假名表 | https://github.com/lazyfoxchan/rime-jaroomaji (37ebca7) | Apache-2.0；随包仅提供假名输入，不包含独立许可的汉字词典 |
| HangulComposer 韩语 2-Set 组合器 | https://github.com/jureuk7/GeulGuard (d3a710e) | MIT；保留原版权与许可证，集成到 GuYiCore |
| OpenCC / glog / gflags / yaml-cpp / leveldb / snappy / marisa | Homebrew formula 对应上游 | 动态库打包进 App，许可证复制到 Resources/Licenses |
| 网络附加词库 | https://github.com/iDvel/rime-ice | 运行时下载 others.dict.yaml；需保留上游来源与许可审查，不宣称为本项目独创 |

本表是来源说明，不替代各组件的完整许可证。每次发布二进制时都需核对构建产物中的实际动态库、许可文本和 LGPL 组件的对应源码及替换条件；不能仅凭仓库有许可证就宣称再分发审查完成。
