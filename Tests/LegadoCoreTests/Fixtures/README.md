# 规则测试样本

这些文件是自动化测试输入，不是 App 的内置书源库。测试包通过 SwiftPM 单独复制该目录，App 目标不会打包它。

- `synthetic-html-rules.json`：最小 HTML 规则，使用保留域名 `fixture.invalid`，验证倒序目录、裸字段提取和带章节变量的内容净化。网络响应在测试中自造，不访问真实网站。
- `legado-js-audio-source.json`：脱敏 JS 听书规则结构样本。地址使用 `fixture.invalid`，用于测试导入字段及脚本保留，不在常规导入测试中请求网络或执行脚本。

新增样本优先自造数据；第三方材料须保留版权与许可。不要把账号凭据或真实付费内容放入 fixture。
