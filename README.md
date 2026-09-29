# 复旦云邮箱桌面卡片

一个无需 Xcode 的轻量 macOS 桌面卡片，每天 09:30 自动通过 IMAP 检查
`@m.fudan.edu.cn` 邮箱，并显示未读数量及最近 5 封未读邮件。

## 使用前准备

1. 登录 https://mail.m.fudan.edu.cn/。
2. 在“设置 → 收发信设置”中开启客户端协议。
3. 在“设置 → 邮箱绑定 → 客户端专用密码”中生成一个新密码。

不要使用统一身份认证密码，也不要把专用密码发给任何人。邮箱地址保存在应用偏好设置中，客户端专用密码只保存在 macOS 登录钥匙串。

## 构建和安装

```bash
cd FudanMailWidget
chmod +x build.sh install.sh
./build.sh
./install.sh
```

应用安装在 `~/Applications/FudanMailWidget.app`，并通过用户级 LaunchAgent
登录自启动。首次启动时输入完整邮箱地址和客户端专用密码；密码只进入
macOS 钥匙串。

卡片可以拖动。右上角按钮分别用于立即检查、修改设置和退出。

## 卸载

退出卡片后执行：

```bash
launchctl bootout "gui/$(id -u)/com.openai.fudan-mail-widget"
rm "$HOME/Library/LaunchAgents/com.openai.fudan-mail-widget.plist"
rm -r "$HOME/Applications/FudanMailWidget.app"
```
