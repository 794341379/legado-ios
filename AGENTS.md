# Legado iOS Agent Guide

本文件是项目根目录的工作说明，供后续代码代理和维护者快速恢复上下文。更完整的开发背景见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。

## 项目概况

- `App/`：SwiftUI 页面、UIKit 阅读器、应用入口和 App 资源。
- `Sources/LegadoCore/`：书源模型、规则引擎、网络、持久化、搜索、阅读和 RSS 核心逻辑。
- `Tests/LegadoCoreTests/`：核心行为、网络模拟和书源兼容测试。
- `Tests/LegadoAppModelsTests/`：页面模型回归测试。
- `Tests/LegadoReaderTests/`、`Tests/LegadoReaderUITests/`：阅读器和模拟器 UI 测试。
- `scripts/`：自检、测试夹具和源码导出工具。
- `Package.swift`：Swift Package 入口；依赖版本由 `Package.resolved` 锁定。

项目最低支持 iOS 15.0，核心包支持 macOS 14+ 测试。主 Xcode 工程是 `Legado.xcodeproj`，应用 Scheme 是 `Legado`。

## 工作规则

- 开始修改前先运行 `git status --short`，保留工作区中已有的用户修改。
- 搜索代码优先使用 `rg` 或 `rg --files`；阅读相关实现和测试后再编辑。
- 手动编辑使用 `apply_patch`，避免无关格式化和大范围重排。
- 不提交证书、私钥、描述文件、真实账号、Authorization token、付费正文或第三方网站凭据。
- 书源在线测试默认不可用；优先使用本地模拟响应和合成夹具，不把一次在线失败误判为代码必然失败。
- 修改工程文件、资源打包或构建设置后必须做对应的构建或资源检查。

## 常用验证

核心测试：

```sh
swift test --disable-sandbox
```

iOS 模拟器构建：

```sh
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/legado-ios-simulator-build \
  CODE_SIGNING_ALLOWED=NO build
```

项目自检：

```sh
sh scripts/self-check.sh
```

修改 `Info.plist` 或工程配置后检查：

```sh
plutil -lint App/Info.plist Legado.xcodeproj/project.pbxproj
git diff --check
```

联网书源、真实设备和 UI 测试需要额外环境，不应因为本地离线回归通过就声称所有线上书源可用。

## 生成未签名 IPA

IPA 是包含 `Payload/Legado.app` 的 ZIP 包。仓库提供 `scripts/build-unsigned-ipa.sh`，通常直接运行：

```sh
./scripts/build-unsigned-ipa.sh
```

脚本默认输出到 `artifacts/`，并用归档后 `.app/Info.plist` 中已经由 Xcode 展开的版本号和构建号命名。如果目标文件已经存在，可通过 `LEGADO_IPA_NAME` 或 `LEGADO_IPA_OUTPUT_DIR` 指定新路径。脚本内部先用 Xcode 命令行生成真机 Release 归档，再手动封装，不使用 `-exportArchive`：

```sh
archive_path="/tmp/legado-ios-unsigned-$(date +%s).xcarchive"
derived_path="/tmp/legado-ios-archive-build-$(date +%s)"

xcodebuild -project Legado.xcodeproj -scheme Legado \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=NO \
  archive

package_dir="artifacts/Legado-unsigned"
mkdir -p "$package_dir/Payload"
cp -R "$archive_path/Products/Applications/Legado.app" "$package_dir/Payload/"
(cd "$package_dir" && zip -qry ../Legado-unsigned.ipa Payload)
```

验证 IPA：

```sh
unzip -t artifacts/Legado-unsigned.ipa
test ! -d artifacts/Legado-unsigned/Payload/Legado.app/_CodeSignature
codesign -dvv artifacts/Legado-unsigned/Payload/Legado.app
```

预期 `codesign` 输出 `code object is not signed at all`。未签名 IPA 不能直接安装到真机，需要后续使用证书重新签名。

## 书源脚本和换源约束

- JavaScript 入口主要在 `Sources/LegadoCore/RuleEngine/JavaScriptRuleEvaluator.swift`。
- Acorn 解析器、执行保护脚本和许可证位于 `Sources/LegadoCore/RuleEngine/Resources/`，并通过 `Package.swift` 与 Xcode 工程打包。
- 默认单次 JavaScript 预算是 10 秒、100,000 次检查。预算覆盖 `jsLib`、登录脚本、嵌套规则、网络等待、正文脚本和正文替换匹配。
- 预算是协作式限制；公开 iOS JavaScriptCore API 无法抢占单次原生正则、内置函数或内存分配，不能将其描述为完整安全沙箱。
- `java.connect(...)` 同时兼容 Android 风格的 `response.body()` 和旧 iOS 规则中的 `response.body`；AES/CBC/PKCS5Padding 由现有桥接实现支持。
- 默认开启 HTTPS 证书校验；兼容无效证书是明确的用户设置，不要在网络层静默放宽校验。
- `BookSourceSwitchService` 只有在目录、映射后的当前章节正文和目录持久化都成功时才返回换源成功。失败应保留原书源和阅读位置，并通过 `BookSourceSwitchFailure` 返回阶段、章节和规则诊断。
- 换源测试应使用合成响应覆盖鉴权请求、目录解析、章节 URL 解密、正文读取、重复章节和失败回滚。

需要更详细的测试夹具、演示参数、RSS/EPUB 回归和发布源流程时，继续阅读 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。
