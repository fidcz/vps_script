#!/bin/bash

# ================= 配置项 =================
SCRIPT_PATH="/usr/local/bin/speed_brush.sh"
LOG_PATH="/tmp/speed_brush.log"

# 单节点单次下载最长时间：180 秒 (3分钟)
SINGLE_RUN_TIME="180"

# 随机暂停触发概率：25%
PAUSE_CHANCE=25

# 伪装 User-Agent
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 国内/国外优质大文件/测速节点混合池 (全球 CDN + 官方长期保留包)
NODES_POOL=(
    # --- 国内高带宽 CDN 节点 ---
    "https://repo.huaweicloud.com/python/3.11.8/Python-3.11.8.tar.xz"
    "https://cdn.npmmirror.com/binaries/node/v20.11.1/node-v20.11.1-linux-x64.tar.xz"
    "https://mirrors.cloud.tencent.com/gradle/gradle-8.5-all.zip"
    "https://mirrors.aliyun.com/macports/distfiles/MacPorts/MacPorts-2.9.1.tar.bz2"
    "https://mirrors.ustc.edu.cn/qtproject/official_releases/qt/6.6/6.6.2/single/qt-everywhere-src-6.6.2.tar.xz"

    # --- 国外/全球 CDN 测速节点 ---
    "https://speed.cloudflare.com/__down?bytes=500000000"
    "https://sgp-ping.vultr.com/vultr.com.1000MB.bin"
    "https://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
    "https://speed.hetzner.de/100MB.bin"
    "https://proof.ovh.net/files/100Mb.dat"
    "https://speedtest.selectel.ru/100MB.bin"
    "https://hkg-hk-ping.vultr.com/vultr.com.1000MB.bin"
)

# 动态随机起止时间全局变量 (每日更新)
START_OFFSET_SEC=0  # 07:00 后的随机延迟秒数 (0 - 1800 秒，即 0~30 分钟)
STOP_OFFSET_SEC=0   # 01:00 后的随机延迟秒数 (0 - 1800 秒，即 0~30 分钟)
LAST_DATE_STAMP=""

# ================= 1. 环境自愈模块 =================
ensure_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        install_pkg curl
    fi

    if ! command -v crontab >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            install_pkg cron
        elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
            install_pkg cronie
            systemctl enable --now crond >/dev/null 2>&1 || service crond start >/dev/null 2>&1
        elif command -v apk >/dev/null 2>&1; then
            install_pkg dcron
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
    fi
}

# ================= 2. 动态随机生成模块 =================

# 每天刷新一次当天的随机启动与停止点 (07:00-07:30 启动 / 01:00-01:30 停止)
update_daily_random_offsets() {
    TODAY=$(TZ='Asia/Shanghai' date '+%Y-%m-%d')
    if [ "$TODAY" != "$LAST_DATE_STAMP" ]; then
        START_OFFSET_SEC=$((RANDOM % 1801))
        STOP_OFFSET_SEC=$((RANDOM % 1801))
        LAST_DATE_STAMP="$TODAY"
        
        START_MIN=$((START_OFFSET_SEC / 60))
        STOP_MIN=$((STOP_OFFSET_SEC / 60))
        echo "[$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')] 📅 更新本日运行计划: 07:$(printf "%02d" $START_MIN) 随机启动，01:$(printf "%02d" $STOP_MIN) 随机停止"
    fi
}

# 校验当前时间是否在允许的随机时间窗口内
is_in_time_window() {
    update_daily_random_offsets

    TODAY_STR=$(TZ='Asia/Shanghai' date '+%Y-%m-%d')
    START_TIMESTAMP=$(TZ='Asia/Shanghai' date -d "$TODAY_STR 07:00:00" +%s)
    START_TIMESTAMP=$((START_TIMESTAMP + START_OFFSET_SEC))

    STOP_TIMESTAMP=$(TZ='Asia/Shanghai' date -d "$TODAY_STR 01:00:00" +%s)
    STOP_TIMESTAMP=$((STOP_TIMESTAMP + STOP_OFFSET_SEC))

    CURRENT_TIMESTAMP=$(TZ='Asia/Shanghai' date +%s)

    if [ "$CURRENT_TIMESTAMP" -ge "$STOP_TIMESTAMP" ] && [ "$CURRENT_TIMESTAMP" -lt "$START_TIMESTAMP" ]; then
        return 1
    else
        return 0
    fi
}

# 生成 80KB/s ~ 100KB/s 之间的随机字节数
get_random_rate() {
    RAND_OFFSET=$((RANDOM % 20481))
    RATE=$((81920 + RAND_OFFSET))
    echo "$RATE"
}

# 生成 8 - 15 分钟 (480 - 900 秒) 的随机暂停秒数
get_random_pause_sec() {
    RAND_OFFSET=$((RANDOM % 421))
    PAUSE_SEC=$((480 + RAND_OFFSET))
    echo "$PAUSE_SEC"
}

# 纯 Bash 格式化秒数为保留 1 位小数的分钟显示 (格式: X.Y)
format_sec_to_min() {
    local sec=$1
    local min=$((sec / 60))
    local remainder_tenths=$(( (sec % 60) * 10 / 60 ))
    echo "${min}.${remainder_tenths}"
}

# ================= 3. Crontab 与安全卸载模块 =================
install_cron() {
    ensure_dependencies

    CURRENT_SCRIPT=$(readlink -f "$0")
    if [ "$CURRENT_SCRIPT" != "$SCRIPT_PATH" ]; then
        SUDO=""
        [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"
        $SUDO cp "$CURRENT_SCRIPT" "$SCRIPT_PATH"
        $SUDO chmod +x "$SCRIPT_PATH"
    fi

    CRON_CMD="*/10 * * * * $SCRIPT_PATH daemon >> $LOG_PATH 2>&1"
    EXISTING_CRON=$(crontab -l 2>/dev/null)

    if echo "$EXISTING_CRON" | grep -Fq "$SCRIPT_PATH"; then
        (echo "$EXISTING_CRON" | grep -v "$SCRIPT_PATH"; echo "$CRON_CMD") | crontab -
        echo "[✓] Crontab 守护进程已更新！"
    else
        (echo "$EXISTING_CRON"; echo "$CRON_CMD") | crontab -
        echo "[✓] Crontab 守护进程部署完成！"
    fi
}

uninstall_cron() {
    # 1. 清理 crontab 定时任务
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -

    # 2. 从 PID 文件精确清理后台引擎进程
    PIDFILE="/tmp/speed_brush.pid"
    if [ -f "$PIDFILE" ]; then
        OLD_PID=$(cat "$PIDFILE")
        kill -9 "$OLD_PID" 2>/dev/null
        rm -f "$PIDFILE"
    fi

    # 3. 安全清理后台 daemon 进程 (通过 grep -v "^$$$" 排除当前脚本自身的 PID，防止整条命令中断)
    MY_PID=$$
    OTHER_PIDS=$(pgrep -f "$SCRIPT_PATH" 2>/dev/null | grep -v "^${MY_PID}$")
    if [ -n "$OTHER_PIDS" ]; then
        echo "$OTHER_PIDS" | xargs -r kill -9 2>/dev/null
    fi

    echo "[✓] 定时任务与后台进程已彻底卸载。"
}

# ================= 4. 主循环引擎 =================
start_engine() {
    ensure_dependencies

    PIDFILE="/tmp/speed_brush.pid"
    if [ -f "$PIDFILE" ]; then
        OLD_PID=$(cat "$PIDFILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            exit 0
        fi
    fi
    echo $$ > "$PIDFILE"

    echo "[$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')] 引擎已启动 (全随机: 80k-100k/s 速率, 8-15分钟 随机暂停)..."

    while true; do
        # 1. 动态时间窗口判断
        if ! is_in_time_window; then
            echo "[$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')] [休眠] 当前属于深夜休息时间段，休眠 10 分钟后复查..."
            sleep 600
            continue
        fi

        # 2. 从节点池随机挑选节点
        COUNT=${#NODES_POOL[@]}
        RAND_IDX=$((RANDOM % COUNT))
        TARGET_URL="${NODES_POOL[$RAND_IDX]}"

        # 3. 动态获取本次下载的随机速率限制 (80k - 100k/s)
        CURRENT_RATE=$(get_random_rate)
        DISPLAY_RATE_KB=$(format_sec_to_min $((CURRENT_RATE * 60 / 1024))) # 计算并显示真实 KB/s

        # 计算约数 KB/s
        RATE_KB=$((CURRENT_RATE / 1024))

        echo "[$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')] 开始下载: $TARGET_URL (限速: ${RATE_KB} KB/s)"

        # 4. 执行下载
        curl -L --fail \
             -A "$UA" \
             --limit-rate $CURRENT_RATE \
             -m $SINGLE_RUN_TIME \
             -Y 20000 -y 15 \
             -s -o /dev/null \
             "$TARGET_URL"

        # 5. 随机暂停判定 (命中概率后，在 8-15 分钟内随机暂停)
        RAND_DICE=$((RANDOM % 100))
        if [ "$RAND_DICE" -lt "$PAUSE_CHANCE" ]; then
            PAUSE_TIME_SEC=$(get_random_pause_sec)
            PAUSE_MIN_DISP=$(format_sec_to_min $PAUSE_TIME_SEC)
            
            echo "[$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')] 🎲 命中 25% 随机概率，暂停 $PAUSE_TIME_SEC 秒 (约 ${PAUSE_MIN_DISP} 分钟)..."
            sleep $PAUSE_TIME_SEC
        else
            # 未命中时，随机微小休眠 5-15 秒
            MINI_SLEEP=$((5 + RANDOM % 11))
            sleep $MINI_SLEEP
        fi
    done
}

# ================= 5. 命令路由 =================
case "$1" in
    install)
        install_cron
        nohup $SCRIPT_PATH daemon >> $LOG_PATH 2>&1 &
        echo "[✓] 全随机模式服务已在后台启动！"
        ;;
    uninstall)
        uninstall_cron
        ;;
    daemon|run)
        start_engine
        ;;
    *)
        echo "使用说明:"
        echo "  $0 install     - 部署后台守护任务并启动长效循环引擎"
        echo "  $0 uninstall   - 停止并卸载守护任务"
        echo "  $0 run         - 前台运行引擎（方便实时查看调试日志）"
        exit 1
        ;;
esac
