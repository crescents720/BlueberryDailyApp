# blueberrySync 云函数

把本目录里的 `index.js` 和 `package.json` 上传到 CloudBase 云函数 `blueberrySync`。

## 控制台操作

1. 进入 CloudBase 环境 `crescents720-d2gwxjftkfbd3035d`。
2. 打开云函数 `blueberrySync`。
3. 在线编辑代码，替换为本目录的 `index.js`。
4. 确认依赖里包含 `@cloudbase/node-sdk`，如果控制台支持上传 `package.json`，一并上传本目录的 `package.json`。
5. 部署函数。

## 测试

浏览器打开：

```text
https://crescents720-d2gwxjftkfbd3035d-1433723768.ap-shanghai.app.tcloudbase.com/blueberrySync
```

应该返回类似：

```json
{"ok":true,"message":"blueberrySync is running","action":"ping"}
```

POST 测试：

```json
{
  "secret": "xiaolanmei-family-2026",
  "action": "ping"
}
```
