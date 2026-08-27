#!/bin/bash

# ================= 配置项 =================
SCRIPT_PATH="/usr/local/bin/speed_brush.sh"
LOG_PATH="/tmp/speed_brush.log"

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

# ================= 1. 环境自愈模块 =================
ensure_dependencies() {
    # 检查 curl
    if ! command -v curl >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未检测到 curl，开始自动安装..."
        install_pkg curl
    fi

    # 检查 crontab
    if ! command -v crontab >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未检测到 cron/crontab，开始自动安装..."
        if command -v apt-get >/dev/null 2>&1; then
            install_pkg cron
        elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
            install_pkg cronie
            systemctl enable --now crond >/dev/null 2>&1 || service crond start >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            install_pkg dcron
        else
            install_pkg cron
        fi
    fi
}

install_pkg() {
    PKG=$1
    SUDO=""
    [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -y && $SUDO apt-get install -y "$PKG"
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y "$PKG"
    elif command -v yum >/dev/null 2>&1; then
        $SUDO yum install -y "$PKG"
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache "$PKG"
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm "$PKG"
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y "$PKG"
    fi
}

# ================= 2. Crontab 部署模块 =================
install_cron() {
    ensure_dependencies

    # 如果当前脚本不在目标路径，则复制自身过去
    CURRENT_SCRIPT=$(readlink -f "$0")
    if [ "$CURRENT_SCRIPT" != "$SCRIPT_PATH" ]; then
        echo "正在复制脚本至系统路径 $SCRIPT_PATH ..."
        SUDO=""
        [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"
        $SUDO cp "$CURRENT_SCRIPT" "$SCRIPT_PATH"
        $SUDO chmod +x "$SCRIPT_PATH"
    fi

    CRON_CMD="*/30 * * * * $SCRIPT_PATH run >> $LOG_PATH 2>&1"
    
    # 获取现有 crontab 内容
    EXISTING_CRON=$(crontab -l 2>/dev/null)

    # 检查是否已经添加过，避免重复注入
    if echo "$EXISTING_CRON" | grep -Fq "$SCRIPT_PATH"; then
        echo "[✓] Crontab 定时任务已存在，无需重复添加！"
    else
        echo "正在写入 Crontab 定时任务 (每30分钟执行一次)..."
        (echo "$EXISTING_CRON"; echo "$CRON_CMD") | crontab -
        echo "[✓] 部署完成！Crontab 已就绪。"
    fi

    echo "日志输出文件: $LOG_PATH"
    echo "你可以通过命令手动测试运行: $SCRIPT_PATH run"
}

uninstall_cron() {
    echo "正在卸载定时任务..."
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo "[✓] 定时任务已安全清除。"
}

# ================= 3. 核心流量任务 =================
run_task() {
    ensure_dependencies

    # 随机延迟执行
    RANDOM_DELAY=$((RANDOM % MAX_SLEEP))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 随机等待 $RANDOM_DELAY 秒后开始下载..."
    sleep $RANDOM_DELAY

    # 挑选国内节点
    DOMESTIC_COUNT=${#DOMESTIC_URLS[@]}
    RANDOM_INDEX=$((RANDOM % DOMESTIC_COUNT))
    SELECTED_DOMESTIC_URL="${DOMESTIC_URLS[$RANDOM_INDEX]}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始流量任务..."

    # 执行国内节点下载
    echo "正在从 [国内节点: $SELECTED_DOMESTIC_URL] 下载..."
    curl --limit-rate $MAX_RATE \
         --max-filesize $MAX_BYTES \
         -s -o /dev/null \
         "$SELECTED_DOMESTIC_URL"

    # 执行国外节点下载
    echo "正在从 [国外节点] 下载..."
    curl --limit-rate $MAX_RATE \
         --max-filesize $MAX_BYTES \
         -s -o /dev/null \
         "$FOREIGN_URL"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 本次流量任务已完成。"
}

# ================= 4. 命令路由处理 =================
case "$1" in
    install)
        install_cron
        ;;
    uninstall)
        uninstall_cron
        ;;
    run)
        run_task
        ;;
    *)
        echo "使用说明:"
        echo "  $0 install    - 自动安装依赖并部署定时任务"
        echo "  $0 uninstall  - 卸载已部署的定时任务"
        echo "  $0 run        - 立即触发一次流量任务"
        exit 1
        ;;
esac
