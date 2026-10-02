# VNC 远程桌面配置与操作说明

本仓库保存本机（Ubuntu 22.04，主机名 `user-NUC12`）**当前可用**的 VNC 远程桌面配置，
以及一套"浏览器窗口跑到物理显示器"问题的修复方案。

## 当前架构（一句话）

物理控制台跑 GNOME/Wayland（`:0`，接显示器），VNC 另外开一个**独立的 XFCE 会话**（显示 `:2`，RFB 端口 `5901`，1920x1080x24），
由 systemd 服务 `vnc-user.service` 开机自启。笔记本用 VNC 客户端连 `5901` 即可看到这个独立桌面。

| 项目 | 值 |
| --- | --- |
| 显示号 | `:2` |
| RFB 端口 | `5901` |
| 分辨率 / 色深 | `1920x1080` / 24 |
| 桌面环境 | XFCE 4（独立会话，带自己的 D-Bus） |
| 启动方式 | systemd 系统服务 `vnc-user.service`（开机自启，失败 10 秒后重试） |
| 启动命令 | `vncserver -fg -localhost no :2 -rfbport 5901 -geometry 1920x1080 -depth 24` |
| 日志 | `~/.vnc/user-NUC12:5901.log`（按小时自动轮转） |

## 仓库内容

```text
README.md                              本文档
vnc/xstartup                           → ~/.vnc/xstartup            VNC 会话启动脚本
vnc/logrotate.conf                     → ~/.vnc/logrotate.conf      会话日志轮转规则
systemd/vnc-user.service               → /etc/systemd/system/vnc-user.service   开机自启（系统服务）
systemd/vnc-log-rotate.service         → ~/.config/systemd/user/    日志轮转（用户服务）
systemd/vnc-log-rotate.timer           → ~/.config/systemd/user/    每小时触发轮转
browser/session-browser                → ~/.local/bin/session-browser           浏览器按会话分流
browser/xfce-helper-google-chrome.desktop → ~/.local/share/xfce4/helpers/         XFCE 浏览器助手覆盖
browser/install.sh                     一键安装上面的浏览器修复
```

> 仓库里**没有** `~/.vnc/passwd`（VNC 密码文件）。密码只存在本机，请自行用 `vncpasswd` 设置。

## 1. 安装依赖

```bash
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-common xfce4 dbus-x11
```

## 2. 设置 VNC 密码

```bash
vncpasswd          # 交互式输入；问 view-only password 时一般选 n
```

密码文件是 `~/.vnc/passwd`（已混淆但**不是**加密），不要提交到任何仓库。
建议用强密码，并优先走 SSH 隧道（见第 6 节）。

## 3. VNC 会话启动脚本 `~/.vnc/xstartup`

```bash
mkdir -p ~/.vnc
cp vnc/xstartup ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup
```

内容（本仓库 `vnc/xstartup`）：

```sh
#!/bin/sh
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
unset WAYLAND_DISPLAY WAYLAND_SOCKET
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
exec dbus-run-session -- xfce4-session
```

每个 `unset` / `export` 都是必要的，别删：

| 语句 | 为什么需要 |
| --- | --- |
| `unset SESSION_MANAGER`、`unset DBUS_SESSION_BUS_ADDRESS` | 否则会误连物理 GNOME 会话的 D-Bus，应用会被激活到物理屏上 |
| `unset WAYLAND_DISPLAY`、`unset WAYLAND_SOCKET` | 否则 GTK/Qt 程序会尝试连物理会话的 Wayland，报 `cannot open display: wayland-0` |
| `export XDG_SESSION_TYPE=x11`、`GDK_BACKEND=x11`、`QT_QPA_PLATFORM=xcb` | 强制走 X11，VNC 会话本身没有 Wayland |
| `dbus-run-session -- xfce4-session` | 给 VNC 会话一套独立的 D-Bus，与物理会话隔离 |

> 注意：早期版本的 `xstartup` 用 `exec startxfce4`。`startxfce4` 会自己再起一个 dbus，
> 在某些环境下会和物理会话串味；当前版本直接用 `dbus-run-session -- xfce4-session` 更干净。

## 4. 开机自启（systemd）

```bash
sudo cp systemd/vnc-user.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vnc-user.service
```

`/etc/systemd/system/vnc-user.service`：

```ini
[Unit]
Description=VNC desktop for user
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=user
Group=user
WorkingDirectory=/home/user
Environment=HOME=/home/user
ExecStart=/usr/bin/vncserver -fg -localhost no :2 -rfbport 5901 -geometry 1920x1080 -depth 24
ExecStop=/usr/bin/vncserver -kill :2
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

- `-fg` 让 `vncserver` 保持前台运行，这样 systemd 才能用 `Type=simple` 正确监管它。**不要**加 `-fg` 之外的后台化参数。
- 改配置后用 `sudo systemctl restart vnc-user.service` 生效。

常用命令：

```bash
systemctl status vnc-user.service          # 看状态
sudo systemctl restart vnc-user.service    # 重启（会断开当前 VNC）
sudo systemctl stop vnc-user.service       # 停止
vncserver -list                            # 列出正在跑的会话
```

## 5. 手动前台启动（调试用）

不动 systemd、临时开一个会话：

```bash
vncserver -localhost no :2 -rfbport 5901 -geometry 1920x1080 -depth 24
vncserver -kill :2
```

如果 `:2` 被占用，换 `:3`（端口 5902）等。

## 6. 从笔记本连接

先查本机内网 IP：

```bash
hostname -I
```

VNC Viewer 连接：

```text
<主机IP>:5901
```

### 更安全的做法：SSH 隧道（推荐）

VNC 的密码握手很弱，别直接暴露在公网。可以只监听本机，再用 SSH 转发：

```bash
# 主机端：改成只监听本机
vncserver -kill :2
vncserver -localhost yes :2 -rfbport 5901 -geometry 1920x1080 -depth 24

# 笔记本端：建立隧道
ssh -N -L 5901:localhost:5901 user@<主机IP>
# 然后 VNC Viewer 连 localhost:5901
```

### 防火墙

```bash
sudo ufw status
sudo ufw allow from <笔记本IP> to any port 5901 proto tcp   # 只放行指定机器
```

## 7. 浏览器窗口弹到物理显示器的问题（已修复）

### 现象

笔记本通过 VNC 连上后，在 VNC 桌面里点"浏览器"，Chrome 窗口却出现在**主机接的物理显示器**上，VNC 里什么都没有。

### 原因

Chrome 对**同一个配置目录只允许一个实例**。物理 GNOME 会话里已经有一个 Chrome 在跑，
它锁住了 `~/.config/google-chrome`；VNC 会话里点浏览器时，新进程只是把请求转发给那个已有实例然后自己退出
（终端会打印 `正在现有的浏览器会话中打开。`），于是窗口出现在物理屏。

所以任何"改默认浏览器"的操作都拦不住它 —— 必须给 VNC 会话一个**独立的配置目录**。

### 修复内容

| 文件 | 作用 |
| --- | --- |
| `~/.local/bin/session-browser` | 按会话分流：物理控制台（`WAYLAND_DISPLAY` 存在或 `DISPLAY=:0`）用原配置；其它会话（VNC）用 `--user-data-dir=~/.config/google-chrome-vnc` |
| `~/.local/share/xfce4/helpers/google-chrome.desktop` | 覆盖系统 XFCE 助手。系统那个是 `X-XFCE-Commands=%B;`，直接调 `google-chrome-stable`，必须覆盖它，否则面板图标绕过一切设置 |
| `~/.config/xfce4/helpers.rc` | 加 `WebBrowser=google-chrome`，让 `exo-open --launch WebBrowser` 固定用上面的助手 |
| `~/.local/share/applications/google-chrome.desktop` | 用户级 GIO 默认浏览器覆盖，管住 `xdg-open`、应用菜单、点击链接 |

一键安装：

```bash
bash browser/install.sh
```

脚本会：安装 wrapper → 装 XFCE 助手覆盖 → 写 `helpers.rc` → 生成 GIO 覆盖 →
**首次**把现有 `~/.config/google-chrome` 复制成 `~/.config/google-chrome-vnc`。

要点：

- 面板按钮仍然是 `exo-open --launch WebBrowser`，`exo-open` 每次点击都会重新读助手配置，所以**不需要重启面板**。
- 物理屏的 Chrome 完全不受影响。
- **数据从此分家**：VNC 里的 Chrome 与物理屏的 Chrome 各自维护历史/书签/Cookie，
  想保持一致就登录 Chrome 同步。
- 首次在 VNC 里打开 Chrome，可能弹出"解锁登录密钥环"，输入登录密码即可
  （Chrome 需要它解密已保存的密码）。VNC 会话没有 PAM 密码，所以这个钥匙环不会自动解锁。

## 8. 会话日志与自动轮转

`~/.vnc/<主机名>:<RFB端口>.log` 是 TigerVNC 的会话日志，例如 `~/.vnc/user-NUC12:5901.log`。

它不只是 Xvnc 自己的输出：`~/.vnc/xstartup` 里所有进程的 **stdout/stderr 都继承了这个文件**
（xfce4-session、dbus、面板、浏览器……），所以任何一个客户端话痨都会把它撑大 ——
本机曾出现单个日志涨到 **1.4 GB**（几小时内），有写满磁盘的风险。

安装轮转（用户级，每小时检查，超过 50 MB 就轮转，保留 3 份并压缩）：

```bash
cp vnc/logrotate.conf ~/.vnc/logrotate.conf
mkdir -p ~/.config/systemd/user
cp systemd/vnc-log-rotate.service systemd/vnc-log-rotate.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now vnc-log-rotate.timer
```

手动立即执行一次／查看状态：

```bash
systemctl --user start vnc-log-rotate.service
systemctl --user list-timers vnc-log-rotate.timer
ls -lh ~/.vnc/*.log*
```

用 `copytruncate` 是因为日志文件描述符在整个会话期间一直被持有，不能靠 rename 换文件。

## 9. 排错

**VNC Viewer 一直 Connecting**

```bash
vncserver -list
ss -lntp | grep 5901          # 期望看到 0.0.0.0:5901 或 *:5901
sudo ufw status
journalctl -u vnc-user.service -n 50 --no-pager
```

如果只看到 `127.0.0.1:5901`，说明启动时是 `-localhost yes`。

**连上后黑屏 / 没有桌面**

```bash
cat ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup
ls -l ~/.vnc/user-NUC12:5901.log
sudo systemctl restart vnc-user.service
```

**窗口跑到物理显示器 / 报 `cannot open display: wayland-0`**

见第 7 节；并确认 `xstartup` 里的 `unset WAYLAND_DISPLAY` 还在。

**日志文件飞快变大**

见第 8 节。先看是谁在刷：

```bash
tail -c 200000 ~/.vnc/user-NUC12:5901.log | sort | uniq -c | sort -rn | head
```

## 10. 安全提醒

- VNC 协议本身的认证很弱，`-localhost no` 会把它暴露给整个局域网。
  能走 SSH 隧道就走隧道；必须直连时用强密码 + 防火墙只放行自己的 IP。
- 本仓库刻意**不包含** VNC 密码文件、SSH 密钥和任何令牌。
- `~/.vnc/passwd` 只是混淆存储，任何拿到该文件的人都能还原出密码。
