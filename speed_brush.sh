#!/bin/bash

# ================= 配置项 =================
SCRIPT_PATH="/usr/local/bin/speed_brush.sh"
LOG_PATH="/tmp/speed_brush.log"

# 最高限速 1M/s (1048576 字节/秒)
MAX_RATE="1048576"
# 最长运行时间 (秒)
MAX_TIME="100"
# 最长随机等待时间 (秒)
MAX_SLEEP=1200

# 伪装 User-Agent
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 精简后 100% 可用且极速的国内大文件节点池
DOMESTIC_URLS=(
    "https://repo.huaweicloud.com/python/3.11.8/Python-3.11.8.tar.xz"
    "https://cdn.npmmirror.com/binaries/node/v20.11.1/node-v20.11.1-linux-x64.tar.xz"
    "https://mirrors.cloud.tencent.com/gradle/gradle-8.5-all.zip"
)

# 经过实测在全球均能跑满带宽的国外节点池 (CDN/云厂商官方测速源)
FOREIGN_URLS=(
    "https://speed.cloudflare.com/__down?bytes=200000000"
    "https://speed.hetzner.de/100MB.bin"
    "https://sgp-ping.vultr.com/vultr.com.1000MB.bin"
    "https://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
    "https://speedtest.selectel.ru/100MB.bin"
)

# ================= 1. 环境自愈模块 =================
ensure_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未检测到 curl，开始自动安装..."
        install_pkg curl
    fi

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

    CURRENT_SCRIPT=$(readlink -f "$0")
    if [ "$CURRENT_SCRIPT" != "$SCRIPT_PATH" ]; then
        echo "正在复制脚本至系统路径 $SCRIPT_PATH ..."
        SUDO=""
        [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"
        $SUDO cp "$CURRENT_SCRIPT" "$SCRIPT_PATH"
        $SUDO chmod +x "$SCRIPT_PATH"
    fi

    CRON_CMD="*/30 * * * * $SCRIPT_PATH run --cron >> $LOG_PATH 2>&1"
    EXISTING_CRON=$(crontab -l 2>/dev/null)

    if echo "$EXISTING_CRON" | grep -Fq "$SCRIPT_PATH"; then
        echo "正在更新已有的 Crontab 定时任务配置..."
        (echo "$EXISTING_CRON" | grep -v "$SCRIPT_PATH"; echo "$CRON_CMD") | crontab -
        echo "[✓] Crontab 定时任务更新成功！"
    else
        echo "正在写入 Crontab 定时任务 (每30分钟执行一次)..."
        (echo "$EXISTING_CRON"; echo "$CRON_CMD") | crontab -
        echo "[✓] 部署完成！Crontab 已就绪。"
    fi
}

uninstall_cron() {
    echo "正在卸载定时任务..."
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo "[✓] 定时任务已安全清除。"
}

# ================= 3. 下载执行模块 (带过低速率防护) =================
download_with_retry() {
    local -n urls=$1
    local mode_name=$2
    local progress_flag=$3
    
    local count=${#urls[@]}
    local start_index=$((RANDOM % count))
    
    for ((i=0; i<count; i++)); do
        local idx=$(((start_index + i) % count))
        local target_url="${urls[$idx]}"
        
        echo -e "\n正在从 [$mode_name: $target_url] 下载..."
        
        # -Y 200000 -y 15: 如果连续 15 秒速度低于 200KB/s，自动放弃并尝试下一个更快的节点
        curl -L --fail \
             -A "$UA" \
             --limit-rate $MAX_RATE \
             -m $MAX_TIME \
             -Y 200000 -y 15 \
             $progress_flag -o /dev/null \
             "$target_url"
        
        local exit_code=$?
        # 0: 正常完成, 28: 达到指定 MAX_TIME (已成功达到100MB流量)
        if [ $exit_code -eq 0 ] || [ $exit_code -eq 28 ]; then
            echo -e "\n[$mode_name] 传输完成 (100MB)。"
            return 0
        else
            echo -e "\n[警告] 该节点速度过慢或连接中断 (退出码: $exit_code)，自动切换下一个节点..."
        fi
    done

    echo "[错误] $mode_name 所有备用节点均无法满足速率要求！"
    return 1
}

# ================= 4. 核心任务 =================
run_task() {
    IS_CRON_MODE=$1
    ensure_dependencies

    CURL_SHOW_PROGRESS="--progress-bar"
    if [ "$IS_CRON_MODE" = "--cron" ] || [ "$IS_CRON_MODE" = "--delay" ]; then
        CURL_SHOW_PROGRESS="-s"
        RANDOM_DELAY=$((RANDOM % MAX_SLEEP))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [定时模式] 随机等待 $RANDOM_DELAY 秒后开始下载..."
        sleep $RANDOM_DELAY
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [手动模式] 跳过延迟，立即开始下载..."
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始任务 (内外网节点各跑 100 秒)..."

    # 执行国内节点下载
    download_with_retry DOMESTIC_URLS "国内节点" "$CURL_SHOW_PROGRESS"

    # 执行国外节点下载
    download_with_retry FOREIGN_URLS "国外节点" "$CURL_SHOW_PROGRESS"

    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 本次任务全部结束。"
}

# ================= 5. 命令路由处理 =================
case "$1" in
    install)
        install_cron
        ;;
    uninstall)
        uninstall_cron
        ;;
    run)
        run_task "$2"
        ;;
    *)
        echo "使用说明:"
        echo "  $0 install           - 自动安装依赖并部署/更新定时任务"
        echo "  $0 uninstall         - 卸载已部署的定时任务"
        echo "  $0 run               - 手动运行（显示实时速率进度，不延迟）"
        echo "  $0 run --delay       - 手动模拟运行（后台模式带随机延迟）"
        exit 1
        ;;
esac
