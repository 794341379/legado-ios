# 第三方许可

小浣熊阅读（项目仓库：<https://github.com/Aminark/legado-ios>）由 Aminark 维护。本项目的新增与修改部分以 GNU GPL v3 提供；第三方材料保留其原版权与适用许可。根目录 [LICENSE](LICENSE) 是完整 GPL v3 文本。

## 阅读 Legado

- 项目：<https://github.com/LegadoTeam/legado>。
- 许可：GNU General Public License v3，完整文本见 [Legado-LICENSE.txt](App/Resources/Legado-LICENSE.txt)。
- 材料：部分业务模块、默认 TXT 目录规则 [txtTocRule.json](App/Resources/txtTocRule.json) 和 HTTP TTS 配置 [httpTTS.json](App/Resources/httpTTS.json)。两份配置对应 `app/src/main/assets/defaultData/` 下的同名文件，原作者署名保留在配置中。
- 版权归 Legado 原作者及其贡献者。Aminark 于 2026-10-13 起修改应用品牌、界面与公开文档；后续修改日期和内容见 [CHANGELOG](CHANGELOG.md) 与 Git 历史。

## SwiftSoup

- 项目：<https://github.com/scinfu/SwiftSoup>。
- 用途：HTML 与 CSS 解析。
- 许可：MIT，完整版权及许可见 [SwiftSoup-LICENSE.txt](App/Resources/SwiftSoup-LICENSE.txt)。

## Kanna

- 项目：<https://github.com/tid-kijyun/Kanna>。
- 用途：XPath 解析。
- 许可：MIT，完整版权及许可见 [Kanna-LICENSE.txt](App/Resources/Kanna-LICENSE.txt)。

## ZIPFoundation

- 项目：<https://github.com/weichsel/ZIPFoundation>，固定版本 `0.9.20`。
- 用途：按需读取 EPUB ZIP 容器与校验资源 CRC。
- 许可：MIT，完整版权及许可见 [ZIPFoundation-LICENSE.txt](App/Resources/ZIPFoundation-LICENSE.txt)。

## Acorn

- 项目：<https://github.com/acornjs/acorn>，固定版本 `8.15.0`。
- 用途：解析书源 JavaScript，为循环与函数插入执行预算检查。
- 材料：`Sources/LegadoCore/RuleEngine/Resources/acorn.js`，来自 `https://unpkg.com/acorn@8.15.0/dist/acorn.js`，SHA-256：`fdb08546776ec6228b03e8d02b40d4ab3255bae5f401adba7ff5dad927ac5c9c`。
- 许可：MIT，完整版权及许可见 [Acorn-LICENSE.txt](Sources/LegadoCore/RuleEngine/Resources/Acorn-LICENSE.txt)。

## 测试数据与演示内容

测试中的规则样本仅用于兼容验证，不打包为 App 默认书源。具体说明见 [测试样本说明](Tests/LegadoCoreTests/Fixtures/README.md)。演示模式使用虚构书籍元数据和项目内演示文本；发布截图不使用个人书架、登录信息或付费章节。

第三方材料继续遵循其各自许可。GPL 覆盖软件的使用和分发，不提供第三方网站、书籍、封面或服务的内容授权。
