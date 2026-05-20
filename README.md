# 小蓝莓的日常

一个用 Godot 4 制作的移动端婴儿喂养日记 App 原型，目标是 Android 和 iOS 双端可用。

## 当前功能

- 主页面：记录、数据可视化、查询与修改三个入口。
- 云同步：通过腾讯云 CloudBase 云函数 `blueberrySync` 同步两台手机的数据；本地 JSON 仍保留，离线时可继续记录。
- 记录：
  - 喂养：母乳/配方奶粉、开始时间、结束时间、奶量、150 字备注。
  - 尿布：小便/大便；小便记录量；大便记录性状、颜色、量、150 字备注。
  - 锻炼：按摩、大动作、精细动作认知、语言、游戏，并带二级项目。
  - 卫生：洗脸、洗澡、游泳。
  - 补充剂：AD、D3、DHA、益生菌、水、铁剂、乳糖酶、其他。
- 数据可视化：按天/按周汇总记录数、奶量和各类型记录，并展示明细。
- 查询与修改：按日期查询历史记录，可编辑或删除。
- 本地存储：数据保存到 Godot 的 `user://blueberry_daily_records.json`。

## 打开方式

1. 安装 Godot 4.x。
2. 用 Godot 打开 `godot_app` 文件夹。
3. 运行主场景 `res://scenes/main.tscn`。

## 移动端导出

- Android：项目已带 `Android Debug` preset，默认导出到 `builds/android/xiaolanmei-debug.apk`。在 Godot 的 Export 面板安装 Android export template 后，选择 `Android Debug`，点击 `Export Project` 即可导出 APK。
- iOS：需要 macOS 和 Xcode。在 Export 面板添加 iOS preset，导出 Xcode project 后签名打包。

如果中文字体在设备上显示异常，可以在 Godot 项目里添加一份支持中文的字体文件，并在 `theme.tres` 中设为默认字体。

## 腾讯云同步

云函数代码在 `cloud_functions/blueberrySync`。当前 App 内置同步地址：

```text
https://crescents720-d2gwxjftkfbd3035d-1433723768.ap-shanghai.app.tcloudbase.com/blueberrySync
```

同步逻辑：

- 首页提供“同步数据”按钮，可手动同步。
- 同步语义是补齐缺失数据：下载本地没有的云端记录，上传云端没有的本地新增记录。
- 手机端不会删除云端数据，也不会覆盖云端已有记录。
- 本地删除只影响当前手机显示。
- 云端全量恢复使用分页下载，避免记录变多后单次响应过大。
- 云同步失败不会影响本地记录。
