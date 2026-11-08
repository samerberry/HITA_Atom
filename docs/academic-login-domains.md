# 三校区教务登录与域名清单

更新日期：2026-11-08。适用工程：独立元服务 `HITA_NEXT_atom`。

## 本次接入范围

在周课表右上角点教务导入，选择本部、威海或深圳，在学校网页完成认证，再读取课表。三校区共用同源 Web fetch 和异步结果回传机制；不会读取或保存登录密码，也不将浏览器 Cookie 复制到原生网络层。

- 本部：本科教务学期、课表、校历，使用本部作息。
- 威海：保留已有本科教务机制及威海作息。
- 深圳：本科教务 JSON 接口，包含学期列表及兼容端点、当前选课学期校准、已选课程信息、个人总课表、教务节次和第一周日期。优先使用教务返回的节次；读取失败时在预览中明确提示使用深圳默认作息。
- 校历读取失败时，要求用户选择第一教学周周一。导入新课表，保留已有课表。
- 未增加研究生系统，也未移植本部另行认证的实践教学、电子实验中心。此清单不包含这些未接入系统的域名。

## 深圳账号页之前停留在 Loading 的修复

无登录状态下，深圳入口跳转到 `trust.hitsz.edu.cn/portal/shortcut.html`，该页初始标题即为 `Loading...`。2026-11-08 检查其公开脚本，网关在初始化时读取 `forceWeb` 决定是否进行客户端检测。旧实现等 `onPageEnd` 后才写入该值并重载，无法保证第一次初始化就走网页登录。

现在通过支持元服务的 `javaScriptOnDocumentStart`，在网关自身脚本之前写入网页模式偏好；仅匹配深圳网关 origin，且只处理顶层页面。每次新文档均生效，不依赖加载完成回调或重复刷新，不读取账号密码。深圳保留 ArkWeb 的原始设备、Mobile 和浏览器内核标识；对未含 Android 标记的 OpenHarmony/HarmonyOS User-Agent 补充 `Android` 移动兼容标记，不再强制 Windows/Chrome 桌面标识。该标记只配置于深圳登录的 WebView，在控制器绑定后、第一次加载前设置一次。网页模式偏好仅用于避免启动 aTrust 原生客户端，与电脑布局无关。

### 账号页之前的 12081

2026-11-08 真机日志显示，`/passport/v1/public/authConfig` 使用 `platform=Unknown`，不断输出 `10000001 handle refresh csrfToken`，约 8 秒后报 `NETWORK_TIMEOUT (12081)`。匿名公开请求复现：`platform=Unknown` 返回 HTTP 422、`code=10000001`、`message=invalid_param in query`；同一原始鸿蒙 UA 配合 `platform=Android` 返回 HTTP 200、`code=0`。网关旧脚本把所有 10000001 都当作 CSRF 失效，无限重试没有新令牌的参数错误，原请求的定时器最终超时。并非 HITA 的课表读取接口或账号密码错误。

因此补充旧网关能识别的移动兼容标记，让其自身 OS 解析生成受支持的参数；不拦截网络请求、不伪造认证结果、不清除学校 Cookie，也不修改网关的安全验证或重试代码。认证后网关实际使用的 `service_center.html#/` 首页亦纳入继续进入教务的已知路由。

在深圳网关及教务的精确 origin 上，文档完成后自动选择可见且可用的「统一身份认证登录」和本科生入口；动态出现的入口通过有上限的 DOM 监听处理，每类选择每个文档最多执行一次，20 秒后或离开页面时清理。不会自动点击普通登录按钮或带密码表单的提交按钮，不读取密码和验证码，不将此脚本注入独立 CAS 站点。统一认证的 `service` 回跳地址由学校网页保留，应用不自行拼装认证票据。

同时监听主页面同文档导航：登录后即使只修改 hash，也会从已识别的门户首页继续打开教务。登录、密码修改、多因素认证、客户端要求和未知移动路由留在学校页面，不能当作已完成认证而强行跳走。成功进入教务后，仍以获取到有效学期列表判断会话就绪。

依据：[Web 属性（文档开始脚本）](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-basic-components-web-attributes/)、[华为 FAQ（onPageBegin 中修改 User-Agent 可能触发重复加载）](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/arkui-uimana-faq-0006/)。自动检查覆盖网页偏好初始化、旧存储兼容、注入范围和认证路由；仍需在真机完成实际账号登录验收，公开网页检查不能证明设备上的唯一故障原因。

## 该在哪个平台配置

这是**元服务的网络/网页域名配置**，不是小艺 Agent 插件的参数配置。

在 HarmonyOS 开发者中心 → 应用管理 → 选择该元服务 → 基础服务 → 元服务域名管理配置。网页导航主要对应“业务域名”；原生 HTTP 网络调用对应“服务器域名 → httpRequest”。本实现的数据请求来自已登录的学校网页，而非 `ohos.net.http`，不要把两类白名单视作可互相替代。

官方业务域名配置流程还要求将平台下载的 `<APPID>.txt` 放在对应网站根目录，验证域名关联关系。学校网站由校方管理，**列出域名并不代表开发者能自行完成验证**，需要校方配合或向平台确认适用接入方式。

官方业务域名仅支持 HTTPS；服务器 httpRequest 域名也要求 HTTPS。本部目前使用 HTTP、1080 端口，威海登录链也可能转到 HTTP。不要为了提交白名单，直接将这些 HTTP 地址改写为未经验证的 HTTPS 地址。添加域名不能保证解除这些限制或满足正式上架条件。

来源：

- [配置业务域名](https://developer.huawei.com/consumer/cn/doc/atomic-guides/agc-help-harmonyos-business-domain/)
- [配置服务器域名](https://developer.huawei.com/consumer/cn/doc/atomic-guides/agc-help-harmonyos-server-domain/)

## 实际入口与重定向

2026-11-07 使用无登录状态的 HTTP 请求观察到以下重定向，未使用学校账号。仅记录域名和路径，不保留查询参数、票据或 Cookie。

| 校区 | 起始地址 | 无登录状态下的重定向 |
| --- | --- | --- |
| 本部 | `http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080/loginCAS` | `https://ivpn.hit.edu.cn:443/controller/v1/public/verify` → 同域 `/portal/shortcut.html` |
| 威海 | `https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/loginCAS` | `http://jwts.hitwh.edu.cn/loginCAS` → `https://ids.hit.edu.cn/authserver/login` |
| 深圳 | `https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main` | `https://trust.hitsz.edu.cn:443/controller/v1/public/verify` → 同域 `/portal/shortcut.html` |

本部的数据地址使用 `vpn`；`ivpn.hit.edu.cn` 是当前服务端返回的认证网关，不能因此从域名清单中删除。程序不会把课表请求发往 `ivpn`。

## 域名/网站列表

“已观察”指上述无登录链路；“兼容”指主应用登录实现或本元服务保留的登录后/备用地址，未通过账号登录验证。HTTPS 业务域名一般填写下面的 origin，不包含 `/loginCAS`、VPN 编码路径和 API 路径。

| 校区/用途 | HTTPS origin | 依据 |
| --- | --- | --- |
| 本部认证网关 | `https://ivpn.hit.edu.cn` | 已观察；服务器跳转可能显式带 `:443` |
| 本部网关兼容地址 | `https://vpn.hit.edu.cn` | 兼容 |
| 统一身份认证 | `https://ids.hit.edu.cn` | 威海链路已观察，本部登录兼容 |
| 威海 WebVPN | `https://webvpn.hitwh.edu.cn` | 现有登录入口 |
| 威海教务 HTTPS 备用源 | `https://jwts.hitwh.edu.cn` | 现有代码兼容；当前实测跳转为 HTTP |
| 深圳代理教务 | `https://jw-hitsz-edu-cn.hitsz.edu.cn` | 新登录入口 |
| 深圳 aTrust 网关 | `https://trust.hitsz.edu.cn` | 已观察；服务器跳转可能显式带 `:443` |
| 深圳直连教务 | `https://jw.hitsz.edu.cn` | 主应用支持的登录后地址；当前电脑无登录请求未连通 |
| 深圳统一认证 | `https://authserver.hitsz.edu.cn` | 主应用认证配置兼容 |

可复制的 HTTPS 列表（包含兼容项，能否提交以平台验证结果为准）：

```text
https://ivpn.hit.edu.cn
https://vpn.hit.edu.cn
https://ids.hit.edu.cn
https://webvpn.hitwh.edu.cn
https://jwts.hitwh.edu.cn
https://jw-hitsz-edu-cn.hitsz.edu.cn
https://trust.hitsz.edu.cn
https://jw.hitsz.edu.cn
https://authserver.hitsz.edu.cn
```

实际存在的 HTTP 地址，**不要假定可按官方 HTTPS 白名单规则直接提交**：

```text
http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080
http://i-hit-edu-cn.vpn.hit.edu.cn:1080
http://jwts.hitwh.edu.cn
```

其中 `i-hit-edu-cn.vpn.hit.edu.cn:1080/portal/home/` 是本部登录后门户的兼容返回页，识别后重新进入教务。本元服务不会主动访问研究生、实践教学或电子实验中心网站。

域名管理中不需要把 VPN 的 `/http/7772…` 编码路径当作新域名。若学校后续引入新的认证 iframe、验证码或网关，需要根据真实加载域名补充，不应无限制添加整个互联网域名或任意通配符。

## 接口路径（供核对，不逐条填入域名栏）

本部基地址为 `http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080`。威海以当前登录文档的 VPN 代理基地址或直连教务 origin 为准：

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/kbcx/queryGrkb` | 验证实际教务会话、学期列表 |
| POST | `/kbcx/queryGrkb` | 指定学期课表，`fhlj=kbcx%2FqueryGrkb&xnxq=…` |
| POST | `/xlcx/queryXlcx` | 校历，`xnxq=…` |

深圳以当前登录后的代理/直连教务 origin 为准，以下全部为 POST：

| 路径 | 用途 |
| --- | --- |
| `/component/queryXnxq` | 学期列表，空 POST 正文 |
| `/component/queryxnxqdata` | 学期列表兼容端点 |
| `/Xsxk/queryXkdqXnxq` | 当前选课学期校准，`p_pylx=1` |
| `/Xsxk/queryYxkc?sf_request_type=ajax` | 已选课程元数据 |
| `/xszykb/queryxszykbzong` | 指定学期个人课表 |
| `/component/queryKbjg` | 教务节次时间 |
| `/component/queryRlZcSj` | 第一教学周日期，`djz=1` |

深圳请求与主应用一致，带 `RoleCode: 01`、`X-Requested-With: XMLHttpRequest` 和表单 Content-Type。Cookie 由浏览器同源请求附带。所有结果通过同步轮询取回，避免 `runJavaScript` 将 Promise 当字符串导致解析失败。深圳总课表请求上限 60 秒，其余 30 秒；关闭、跳转、超时会终止请求并清理结果。

## 验证与交付

- Node 检查覆盖三校区路由隔离、本部当前 VPN 地址、深圳请求方法/表单/元数据/节次/校历、页面跳转取消及威海回归。
- 构建使用本机 DevEco SDK，产物为 `entry/build/default/outputs/default/entry-default-signed.hap`，调试签名。
- 未启动模拟器，未安装到手机，未进行学校账号端到端登录，未替用户更改任何平台白名单或发布配置。
