#!/bin/bash

# ================= 基础参数配置 =================
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

# ================= 脚本逻辑执行 =================

# 1. 随机延迟执行
RANDOM_DELAY=$((RANDOM % MAX_SLEEP))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 随机等待 $RANDOM_DELAY 秒后开始下载..."
sleep $RANDOM_DELAY

# 2. 从国内节点池随机挑选 1 个 URL
DOMESTIC_COUNT=${#DOMESTIC_URLS[@]}
RANDOM_INDEX=$((RANDOM % DOMESTIC_COUNT))
SELECTED_DOMESTIC_URL="${DOMESTIC_URLS[$RANDOM_INDEX]}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始刷流量任务..."

# 3. 执行国内节点下载
echo "正在从 [国内节点: $SELECTED_DOMESTIC_URL] 下载..."
curl --limit-rate $MAX_RATE \
     --max-filesize $MAX_BYTES \
     -s -o /dev/null \
     "$SELECTED_DOMESTIC_URL"

# 4. 执行国外节点下载
echo "正在从 [国外节点] 下载..."
curl --limit-rate $MAX_RATE \
     --max-filesize $MAX_BYTES \
     -s -o /dev/null \
     "$FOREIGN_URL"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 本次刷流量任务已完成。"
