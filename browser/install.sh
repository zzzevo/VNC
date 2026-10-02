#!/bin/sh
# 安装"浏览器窗口跑到物理显示器"的修复。
#
# 解决：VNC 会话里点浏览器，Chrome 窗口出现在主机物理屏而不是 VNC 里。
# 原理见 README 第 7 节；核心是给 VNC 会话一个独立的 Chrome 配置目录。
#
# 用法：bash browser/install.sh
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
H=${HOME:?HOME 未设置}

echo "==> 安装 session-browser"
mkdir -p "$H/.local/bin"
install -m 755 "$HERE/session-browser" "$H/.local/bin/session-browser"

echo "==> 安装 XFCE 浏览器助手覆盖"
mkdir -p "$H/.local/share/xfce4/helpers"
sed "s|/home/user/.local/bin/session-browser|$H/.local/bin/session-browser|g" \
    "$HERE/xfce-helper-google-chrome.desktop" \
    > "$H/.local/share/xfce4/helpers/google-chrome.desktop"
chmod 644 "$H/.local/share/xfce4/helpers/google-chrome.desktop"

echo "==> 固定 XFCE 的 WebBrowser 助手"
mkdir -p "$H/.config/xfce4"
touch "$H/.config/xfce4/helpers.rc"
if grep -q '^WebBrowser=' "$H/.config/xfce4/helpers.rc"; then
    sed -i 's|^WebBrowser=.*|WebBrowser=google-chrome|' "$H/.config/xfce4/helpers.rc"
else
    printf 'WebBrowser=google-chrome\n' >> "$H/.config/xfce4/helpers.rc"
fi

echo "==> 生成用户级 GIO 默认浏览器覆盖（管住 xdg-open / 应用菜单）"
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    mkdir -p "$H/.local/share/applications"
    sed "s|/usr/bin/google-chrome-stable|$H/.local/bin/session-browser|g" \
        /usr/share/applications/google-chrome.desktop \
        > "$H/.local/share/applications/google-chrome.desktop"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$H/.local/share/applications" || true
    fi
else
    echo "    未找到 /usr/share/applications/google-chrome.desktop，跳过"
fi

echo "==> 准备 VNC 独立配置目录"
if [ -d "$H/.config/google-chrome-vnc" ]; then
    echo "    已存在，跳过（删掉 ~/.config/google-chrome-vnc 可重新生成）"
elif [ -d "$H/.config/google-chrome" ]; then
    cp -a "$H/.config/google-chrome" "$H/.config/google-chrome-vnc"
    rm -f "$H/.config/google-chrome-vnc"/Singleton* 2>/dev/null || true
    echo "    已从 ~/.config/google-chrome 复制一份（书签/历史/密码都在）"
else
    echo "    没有现成的 Chrome 配置，首次启动会自动新建"
fi

echo
echo "完成。直接在 VNC 会话里点浏览器图标即可，窗口会开在 VNC 里。"
echo "注意：物理屏的 Chrome 不受影响，但两边数据从此各自独立。"
