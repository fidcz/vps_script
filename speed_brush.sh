#!/bin/bash

# ================= 1. 环境检查与自动完善 =================
ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未检测到 curl，开始自动安装依赖..."

    # 获取当前权限前缀
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            echo "[错误] 缺少 root 权限且系统中未找到 sudo，无法自动安装 curl！"
            exit 1
        fi
    fi

    # 自动识别系统包管理器并安装 curl
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -y && $SUDO apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
        $SUDO yum install -y curl
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache curl
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm curl
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y curl
    else
        echo "[错误] 未识别的包管理器，请手动安装 curl！"
        exit 1
    fi

    # 验证安装是否成功
    if command -v curl >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] curl 环境安装成功！"
    else
        echo "[错误] curl 安装失败，请检查网络或包管理器源！"
        exit 1
    fi
}

# 执行环境检查
ensure_curl

# ================= 2. 基础参数配置 =================
# 最高限速 1M/s (1048576 字节/秒)
MAX_RATE="1048576"

# 单次最大下载量 100M (104857600 字节)
MAX_BYTES="104857600"

# 最长随机等待时间 (秒)，20分钟内随机启动
MAX_SLEEP=1200

# 国内非系统镜像节点池
DOMESTIC_URLS=(
    "https://mirrors.cloud.tencent.com/nodejs-release/v20.11.1/node-v20.11.1-linux-x64.tar.xz"
    "https://registry.npmmirror.com/-/binary/echarts/5.4.3/echarts-5.4.3.tgz"
    "https://mirrors.163.com/mysql/Downloads/MySQL-8.0/mysql-8.0.36-linux-glibc2.28-x86_64.tar.xz"
    "https://npmmirror.com/mirrors/electron/28.2.0/electron-v28.2.0-linux-x64.zip"
    "https://repo.huaweicloud.com/python/3.11.8/Python-3.11.8.tar.xz"
    "https://mirrors.tuna.tsinghua.edu.cn/chromium-browser-snapshots/Linux_x64/1100000/chrome-linux.zip"
    "https://mirrors.volces.com/android/repository/android-ndk-r26b-linux.zip"
)

# 国外测试节点
FOREIGN_URL="https://speed.cloudflare.com/__down?bytes=104857600"

# ================= 3. 脚本逻辑执行 =================

# 3.1 随机延迟执行
RANDOM_DELAY=$((RANDOM % MAX_SLEEP))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 随机等待 $RANDOM_DELAY 秒后开始下载..."
sleep $RANDOM_DELAY

# 3.2 从国内节点池随机挑选 1 个 URL
DOMESTIC_COUNT=${#DOMESTIC_URLS[@]}
RANDOM_INDEX=$((RANDOM % DOMESTIC_COUNT))
SELECTED_DOMESTIC_URL="${DOMESTIC_URLS[$RANDOM_INDEX]}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始刷流量任务..."

# 3.3 执行国内节点下载
echo "正在从 [国内节点: $SELECTED_DOMESTIC_URL] 下载..."
curl --limit-rate $MAX_RATE \
     --max-filesize $MAX_BYTES \
     -s -o /dev/null \
     "$SELECTED_DOMESTIC_URL"

# 3.4 执行国外节点下载
echo "正在从 [国外节点] 下载..."
curl --limit-rate $MAX_RATE \
     --max-filesize $MAX_BYTES \
     -s -o /dev/null \
     "$FOREIGN_URL"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 本次刷流量任务已完成。"
