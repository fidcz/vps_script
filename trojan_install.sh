#!/bin/sh
#=========================================================
# LXC 极简小鸡通用版: Trojan-Go 一键安装脚本
# 自适应包管理器 (apt/apk) 与守护进程 (Systemd/OpenRC)
#=========================================================

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 权限运行此脚本"
    exit 1
fi

echo "=== LXC Trojan-Go 通用极简安装向导 ==="

# [新增] 自动检测并使用对应的包管理器安装依赖
echo "正在检查并安装必要系统依赖 (curl, unzip, openssl)..."
if command -v apk >/dev/null 2>&1; then
    # Alpine 系统
    apk update >/dev/null 2>&1
    apk add --no-cache curl unzip openssl >/dev/null 2>&1
elif command -v apt-get >/dev/null 2>&1; then
    # Debian/Ubuntu 系统
    apt-get update >/dev/null 2>&1
    apt-get install -y curl unzip openssl >/dev/null 2>&1
else
    echo "❌ 错误: 未找到支持的包管理器 (apt/apk)，请手动安装 curl, unzip, openssl。"
    exit 1
fi

echo "========================================================="

# 1. 收集用户输入 (端口)
read -p "请输入 Trojan-Go 监听端口 (直接回车默认使用 10000): " PORT
PORT=${PORT:-10000}

# 2. 收集用户输入 (密码)
read -p "请输入 Trojan-Go 密码 (直接回车将随机生成 UUID): " PASSWORD
if [ -z "$PASSWORD" ]; then
    if [ -r /proc/sys/kernel/random/uuid ]; then
        PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        PASSWORD=$(openssl rand -hex 16 | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
    fi
    echo " -> 检测到密码为空，已为您生成随机 UUID 密码: $PASSWORD"
fi

echo ""
echo "[1/6] 正在为 bing.com 生成 10年有效期自签证书..."
mkdir -p /etc/trojan-go
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/trojan-go/server.key \
    -out /etc/trojan-go/server.crt \
    -subj "/C=US/ST=Washington/L=Redmond/O=Microsoft Corporation/CN=bing.com" 2>/dev/null

echo "[2/6] 正在下载并配置 Trojan-Go 二进制文件..."
curl -sL -o /tmp/trojan-go.zip https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
unzip -o /tmp/trojan-go.zip -d /tmp/trojan-go >/dev/null 2>&1
mv /tmp/trojan-go/trojan-go /usr/local/bin/
chmod +x /usr/local/bin/trojan-go
rm -rf /tmp/trojan-go.zip /tmp/trojan-go

echo "[3/6] 正在生成 config.json 配置文件..."
cat > /etc/trojan-go/config.json <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": $PORT,
    "remote_addr": "13.107.21.200",
    "remote_port": 80,
    "password": [
        "$PASSWORD"
    ],
    "ssl": {
        "cert": "/etc/trojan-go/server.crt",
        "key": "/etc/trojan-go/server.key",
        "sni": "bing.com"
    },
    "router": {
        "enabled": false
    }
}
EOF

echo "[4/6] 正在检测系统初始化进程并注册服务..."
# [新增] 核心逻辑：优先 Systemd，降级 OpenRC
if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
    echo " -> 检测到 Systemd，正在写入 service 配置..."
    cat > /etc/systemd/system/trojan-go.service <<-EOF
[Unit]
Description=Trojan-Go Proxy Service
After=network.target network-online.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable trojan-go >/dev/null 2>&1
    
    echo "[5/6] 正在启动 Trojan-Go 服务..."
    systemctl restart trojan-go

elif command -v rc-update >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
    echo " -> 检测到 OpenRC (Alpine)，正在写入 init.d 配置..."
    cat > /etc/init.d/trojan-go <<'EOF'
#!/sbin/openrc-run

name="trojan-go"
description="Trojan-Go Proxy Service"
command="/usr/local/bin/trojan-go"
command_args="-config /etc/trojan-go/config.json"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/trojan-go.log"
error_log="/var/log/trojan-go.err"

depend() {
    need net
    after dns
}
EOF
    chmod +x /etc/init.d/trojan-go
    rc-update add trojan-go default >/dev/null 2>&1
    
    echo "[5/6] 正在启动 Trojan-Go 服务..."
    rc-service trojan-go restart >/dev/null 2>&1
else
    echo "❌ 错误: 未检测到 Systemd 或 OpenRC，无法自动注册服务。请手动运行 Trojan-Go。"
    exit 1
fi

echo "[6/6] 正在获取公网 IP 并生成分享链接..."
PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP="你的公网IP或DDNS"
fi

RANDOM_SUFFIX=$(openssl rand -hex 2)
NODE_NAME="LXC-Nat-${RANDOM_SUFFIX}"
TROJAN_LINK="trojan://${PASSWORD}@${PUBLIC_IP}:${PORT}?sni=bing.com&allowinsecure=1#${NODE_NAME}"

echo ""
echo "========================================================="
echo " 🎉 Trojan-Go 安装与配置成功！"
echo "========================================================="
echo " ⬇️  一键分享链接 (请复制以下链接导入客户端)："
echo ""
echo -e "\033[32m${TROJAN_LINK}\033[0m"
echo ""
echo " ⚠️ 注意："
echo " 如果 ${PUBLIC_IP} 不是你 NAT 机器的正确入口公网 IP，"
echo " 请在客户端中手动将其修改为正确的 IP 或 DDNS 域名。"
echo "========================================================="
echo " 管理命令提示:"

# [新增] 动态显示管理命令
if [ "$INIT_SYSTEM" = "systemd" ]; then
    echo " 启动: systemctl start trojan-go"
    echo " 停止: systemctl stop trojan-go"
    echo " 状态: systemctl status trojan-go"
    echo " 日志: journalctl -u trojan-go -f"
elif [ "$INIT_SYSTEM" = "openrc" ]; then
    echo " 启动: rc-service trojan-go start"
    echo " 停止: rc-service trojan-go stop"
    echo " 状态: rc-service trojan-go status"
    echo " 日志: cat /var/log/trojan-go.err"
fi
echo "========================================================="
