# 开发与代码复用

本工程从 [HITA NEXT](https://github.com/samerberry/HITA_NEXT) 提取周课表和课程编辑能力，可作为独立的 DevEco Studio 工程构建，不要求本机同时存在主应用源码。

## 共享代码与元服务适配


`scripts/sync-shared.cjs` 从完整版工程提取课程功能和教务解析器的相对导入依赖闭包；默认来源为旁边的 `HITA_NEXT-0.3.0`，也可传入源工程路径。`shared-sources.json` 记录来源和提取后的 SHA-256，以下文件针对元服务适配：

1. `RdbHelper.ets`：保留编辑器所需接口，底层替换成沙箱 JSON 存储。当前 SDK 不允许元服务使用 `relationalStore`。每次写入在副本中完成，完整写入临时文件、关闭并重命名成功后才更新内存；失败保留原文件和原内存，不用空数据覆盖读取失败的内容。
2. `DetailActionBar.ets`：去掉学习待办入口。
3. `CompatibleLightModifier.ets`：去掉元服务不支持的额外 `RenderNode/drawing` 光感反馈，保留可用的系统卡片和弹层材质。

`RdbHelper` 的名称仅用于兼容共享编辑器，本工程不创建关系型数据库。数据文件为元服务私有沙箱下 `filesDir/atomic-timetable-v1.json`。课表和颜色均独立于完整 HITA NEXT；没有自动读取完整应用数据的流程。

同步共享源代码：

```powershell
node scripts/sync-shared.cjs
```

适配后的存储实现源位于 `scripts/adapters/RdbHelper.ets`。需要修改它时改这里，然后同步；避免直接修改会被同步脚本覆盖的提取文件。同步脚本仅删除上次清单中已不再依赖的提取文件。

## 同步前注意

共享代码已包含在本仓库中，日常构建不需要运行同步脚本。同步会覆盖提取清单中的共享文件及部分资源；只有计划从主应用更新公共实现时才运行，并核对元服务已有适配和差异。

主应用不在默认位置时，可显式指定来源：

```powershell
node scripts/sync-shared.cjs C:/path/to/HITA_NEXT
```

## 元服务图标

图标由 DevEco Studio 的 `New > Image Asset` 生成，使用原始 H 标志和 `#C4DDFD` 浅蓝外环。

- 原始素材：`AppScope/resources/base/media/app_icon.png`（1024 × 1024），保留供重新生成。
- 随包图标：`AppScope/resources/base/media/atom_icon.png`（512 × 512），生成后移入应用公共资源目录，应用图标、入口图标与启动窗口统一引用 `$media:atom_icon`。
- 平台上传图标：`assets/appgallery/atom_icon.png`（216 × 216），用于 AppGallery Connect。

重新生成时，在 `entry` 模块打开 Image Asset，名称填写 `atom_icon`，保存路径选择 `assets/appgallery`；将生成在模块资源目录的 512 像素图标同步到上述公共资源目录。

## 本地签名

远程仓库的 `build-profile.json5` 不包含个人签名材料。首次克隆后，在 DevEco Studio 的 `File > Project Structure > Signing Configs` 为本机配置元服务签名。调试 Profile 必须包含验收设备，且应与本元服务的 App ID 和包名对应。

当前开发机器保留自己的本地签名配置；提交 `build-profile.json5` 时仅保留 SDK、产品和模块配置。签名文件、密码、`.env`、IDE 状态、构建日志和软件包不应提交到仓库。

## 检查与构建

运行方式见 [README](../README.md#开发与构建)。`scripts/atomic-timetable.test.cjs` 覆盖存储写入、课程批量编辑与撤销、三校区接口适配、同源请求与取消、深圳网关初始化及移动浏览器兼容。

这些检查不替代学校账号的真机登录验收。自动化脚本不会启动模拟器、安装应用或提交平台配置。
