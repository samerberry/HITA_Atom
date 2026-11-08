<p align="center">
  <img src="AppScope/resources/base/media/app_icon.png" width="128" alt="HITA Atom 图标">
</p>

# HITA Atom

当前版本：**0.1.0**（开发中）。

HITA Atom 是从 [HITA NEXT](https://github.com/samerberry/HITA_NEXT) 提取的 HarmonyOS 元服务，采用 ArkTS 与 ArkUI 原生实现，为哈尔滨工业大学一校三区学生提供轻量的周课表查看、课程编辑和教务课表导入功能。

项目沿用 HITA NEXT 的课程布局与交互习惯，将主要操作集中在周课表页面。打开即可查看课程，也可以手动添加课程或从教务系统导入课表。

## 核心功能

### 周课表

- 按周展示课程、日期和上课时间，左上角显示当前查看的教学周。
- 点击周次选择教学周，支持左右滑动切换及切换动画。
- 离开当前周后，可通过悬浮按钮快速返回本周。
- 课程按照实际开始时间和持续时间绘制，重叠课程自动分栏。
- 显示课程名称和教室，长教室名支持滚动展示。
- 时间轴根据当前查看周的课程安排扩展。
- 跟随系统深浅色，适配元服务胶囊及系统导航条。

### 课程管理

- 手动添加课程，支持按具体日期或教学周选择上课日期。
- 支持按节次或具体时间添加、修改课程。
- 查看课程详情、修改课程颜色，保留批量修改范围与撤销操作。
- 删除当前课程块对应的课次，保留其他日期的课程。
- 首次手动添加时，可设置第一教学周的周一、教学周数及校区作息。

### 教务导入

- 提供本部、威海和深圳校区的本科教务登录入口。
- 在学校网页中完成账号登录及验证，再读取学期、课表和校历。
- 深圳支持统一身份认证及本科生入口衔接，并适配网关的移动浏览器识别。
- 导入前可选择学期并确认开学日期；校历不可用时手动选择第一教学周的周一。
- 使用对应校区的作息，课程按教学周及单双周展开。
- 导入结果保存为新课表，保留已有的手动课表。

三校区登录仍在持续适配，实际可用性受学校网络、统一认证和教务接口状态影响。当前未接入研究生教务及本部独立实验系统。访问地址、网关兼容与域名配置见 [教务登录与域名说明](docs/academic-login-domains.md)。

## 与 HITA NEXT 的关系

HITA Atom 聚焦周课表，复用主应用的课表绘制、课程编辑、模型及教务解析器，并针对元服务的能力范围进行适配。

当前不包含今日页、更多页、小艺助手、学习待办、背景媒体、桌面卡片、通知和日历同步。元服务与主应用使用各自独立的本地数据，不会自动同步课表。

## 技术基线

- 开发语言：ArkTS。
- UI：ArkUI 声明式界面，使用 `AtomicServiceNavigation`。
- 应用模型：Stage 元服务，`bundleType: atomicService`。
- 网页登录：ArkWeb。
- 教务请求：通过已登录网页发起同源 `fetch`，沿用浏览器登录会话。
- 本地课表：沙箱 JSON 存储，写入失败时保留已有数据。
- 设备声明：phone、tablet 和 2in1。
- 最低兼容 SDK：6.1.0(23)；编译与目标 SDK：26.0.0。

课表导入与展示数据流：

```text
学校网页认证 → 同源教务请求 → 课程解析与预览 → 本地存储 → 周课表
```

## 关键结构

```text
HITA_Atom/
├── AppScope/                         # 元服务名称、图标与应用配置
├── entry/
│   └── src/main/
│       ├── ets/
│       │   ├── atomic/               # 元服务入口界面、登录、导入与独立存储
│       │   ├── entryability/         # EntryAbility 入口及窗口适配
│       │   ├── pages/                # 课程添加、编辑页面
│       │   ├── feature/timetable/    # 周课表绘制、课程卡片与详情
│       │   ├── feature/eas/          # 教务模型与课程解析
│       │   └── common/               # 共享模型、组件、主题和存储接口
│       └── resources/                # 字符串、颜色及资源
├── docs/                             # 登录域名和开发说明
├── scripts/                          # 构建、代码提取与回归检查
├── shared-sources.json               # 共享代码来源及提取校验记录
├── build-profile.json5
└── hvigorfile.ts
```

共享源码已包含在仓库中，可以直接独立开发和构建。代码提取、存储适配及后续同步方式见 [开发与代码复用](docs/development.md)。

## 开发与构建

### 环境要求

- 支持 HarmonyOS SDK 26.0.0 的 DevEco Studio 及配套 SDK。
- Node.js，可使用 DevEco Studio 自带版本运行辅助脚本。
- 真机调试需要与元服务包名匹配的签名及设备 Profile。

### 使用 DevEco Studio

1. 克隆仓库：

   ```bash
   git clone https://github.com/samerberry/HITA_Atom.git
   ```

2. 使用 DevEco Studio 打开仓库根目录，等待工程同步完成。
3. 在 `File > Project Structure > Signing Configs` 中为本机配置元服务签名。
4. 选择 `entry` 模块进行构建，使用已签名的 HAP 在真机验收。

本工程使用独立元服务身份，包名以 `AppScope/app.json5` 为准。签名须与平台登记的元服务 App ID 对应，不复用 HITA NEXT 主应用的 Profile。

### 命令行构建

在 Windows PowerShell 中进入仓库根目录。脚本默认使用 `C:\Program Files\Huawei\DevEco Studio`：

```powershell
# 调试构建，生成 HAP 与 APP
./scripts/build.ps1

# Release 构建
./scripts/build.ps1 -BuildMode release
```

HAP 产物位于：

```text
entry/build/default/outputs/default/
```

配置签名后通常生成 `entry-default-signed.hap`，用于真机调试。应用市场上传使用发布签名构建的 `.app`；仅切换为 Release 模式不会将调试签名变为发布签名。

### 回归检查

```bash
node --test scripts/atomic-timetable.test.cjs
```

检查覆盖课程规则、存储完整性、三校区导入和登录路由。真实学校账号登录、手势和视觉体验由真机验收。

## 数据与隐私

- 教务登录与数据请求直接访问学校的统一认证、网关及教务系统。
- 账号密码由用户在学校页面输入，本项目不读取或保存密码。
- 教务请求使用 ArkWeb 管理的 Cookie，不将认证票据复制到原生网络层。
- 课表及课程颜色保存在元服务自己的沙箱中，与主应用数据独立。
- 学校认证方式或接口发生变化时，相关功能可能需要同步适配。

本项目不是哈尔滨工业大学官方应用。发布前仍需完成元服务业务域名、隐私政策及发布签名等平台配置。

## 致谢

- [HITA NEXT](https://github.com/samerberry/HITA_NEXT)：周课表、课程编辑、公共组件及教务解析实现的来源。
- [HITA Android](https://github.com/HIT-A/HITA_Android)：HITA 系列的主要功能逻辑和数据结构参考。
- [HITA Aura](https://github.com/HIT-A/HITA-Aura)：HITA 系列界面布局与跨平台体验参考。
- HITA 系列项目的开发者与贡献者。

## 授权状态

本仓库当前未附带独立的 `LICENSE` 文件。代码与资源的使用请遵循相应原项目的授权声明；其他使用许可待后续明确。
