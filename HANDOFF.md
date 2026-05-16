# 小蓝莓的日常 - Codex 交接说明

## 项目概况

这是一个 Godot 4 移动端 App，用于记录“小蓝莓”的日常，包括喂养、尿布、锻炼、卫生、补充剂，并支持按天/按周查看数据总览、按日期查询和修正记录。

项目目录：

```text
godot_app/
```

主场景：

```text
res://scenes/main.tscn
```

主要脚本：

```text
res://scripts/main.gd
res://scripts/data_store.gd
res://scripts/sync_service.gd
```

## 当前能力

- Android APK 已可导出并运行。
- 本地数据保存到 Godot 的 `user://blueberry_daily_records.json`。
- 已接入腾讯云 CloudBase 云同步。
- 两台手机可以通过同一个 CloudBase 云函数同步记录。
- 保存、修改、删除后会自动尝试同步。
- 首页有“同步数据”按钮，可手动同步。
- 删除使用软删除，避免另一台手机把旧记录同步回来。

## 腾讯云 CloudBase

环境 ID：

```text
crescents720-d2gwxjftkfbd3035d
```

同步接口：

```text
https://crescents720-d2gwxjftkfbd3035d-1433723768.ap-shanghai.app.tcloudbase.com/blueberrySync
```

云函数目录：

```text
cloud_functions/blueberrySync/
```

云函数代码：

```text
cloud_functions/blueberrySync/index.js
cloud_functions/blueberrySync/package.json
```

数据库集合：

```text
records
```

## Android 导出注意事项

Android preset 在：

```text
export_presets.cfg
```

必须确保下面权限为 true，否则手机端无法同步：

```text
permissions/internet=true
permissions/access_network_state=true
```

包名：

```text
com.xiaolanmei.daily
```

## iOS 后续

iOS 需要在 macOS + Xcode 上导出。Godot 项目本身可跨平台，腾讯云同步使用 HTTPS，不依赖 Android 专属能力。后续要在 Mac 上：

1. 安装 Godot 4.x。
2. 安装 Xcode。
3. 安装 Godot iOS export templates。
4. 添加 iOS export preset。
5. 导出 Xcode project。
6. 在 Xcode 里用 Apple ID 签名并安装到 iPhone。

## 推荐云端保存方式

建议把本项目放到一个新的私有 Git 仓库，例如：

```text
xiaolanmei-daily
```

不要直接推到当前旧仓库 `BossRun`，除非明确想把两个项目混在一起。

推荐只提交：

```text
godot_app/
```

当前仓库根目录里还有旧微信小游戏相关文件，例如：

```text
app.json
pages/game/
assets/
```

它们不是“小蓝莓的日常”的核心工程。
