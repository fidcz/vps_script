#!/bin/sh

# =========================================================
# 华为云 DNS 自动/手动切换与测速管理脚本 (纯原生 POSIX Shell)
# =========================================================

CONFIG_FILE="$HOME/.huawei_dns_config.env"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$PWD/$0")"

# 1. 自动检测系统并安装依赖
check_and_install_deps() {
    MISSING_CMDS=""
    for cmd in curl openssl awk crontab tr; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_CMDS="$MISSING_CMDS $cmd"
        fi
    done

    if [ -n "$MISSING_CMDS" ]; then
        echo "[INFO] 检测到缺失必要工具:$MISSING_CMDS，正在尝试自动安装..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq curl openssl gawk cron coreutils
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y -q curl openssl gawk crontabs coreutils
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y -q curl openssl gawk crontabs coreutils
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add --no-cache curl openssl gawk cronie coreutils
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -Sy --noconfirm curl openssl gawk cronie coreutils
        elif command -v opkg >/dev/null 2>&1; then
            opkg update && opkg install curl openssl-util gawk cron coreutils
        else
            echo "[ERROR] 未能识别当前系统的包管理器，请手动安装:$MISSING_CMDS"
            exit 1
        fi
    fi
}

# 2. 加载本地配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi
}

# 3. 校验必要配置是否存在
check_config_env() {
    load_config
    if [ -z "$HUAWEI_AK" ] || [ -z "$HUAWEI_SK" ] || [ -z "$HUAWEI_ZONE_ID" ] || \
       [ -z "$HUAWEI_RECORDSET_ID" ] || [ -z "$DNS_RECORD_NAME" ] || \
       [ -z "$MAIN_IP" ] || [ -z "$BACKUP_IP" ] || [ -z "$SPEED_THRESHOLD_MBPS" ]; then
        echo "[WARNING] 关键配置尚未设置或不完整！"
        configure_settings
    fi
}

# 4. 交互式设置与保存配置
configure_settings() {
    load_config
    echo ""
    echo "========================================================="
    echo "               设置 / 修改系统参数"
    echo "========================================================="
    
    printf "请输入 华为云 HUAWEI_AK [%s]: " "${HUAWEI_AK:-}"
    read input; [ -n "$input" ] && HUAWEI_AK="$input"

    printf "请输入 华为云 HUAWEI_SK [%s]: " "${HUAWEI_SK:-}"
    read input; [ -n "$input" ] && HUAWEI_SK="$input"

    printf "请输入 HUAWEI_ZONE_ID [%s]: " "${HUAWEI_ZONE_ID:-}"
    read input; [ -n "$input" ] && HUAWEI_ZONE_ID="$input"

    printf "请输入 HUAWEI_RECORDSET_ID [%s]: " "${HUAWEI_RECORDSET_ID:-}"
    read input; [ -n "$input" ] && HUAWEI_RECORDSET_ID="$input"

    printf "请输入 域名解析记录名称 (如 example.com.) [%s]: " "${DNS_RECORD_NAME:-}"
    read input; [ -n "$input" ] && DNS_RECORD_NAME="$input"

    printf "请输入 主 IP 地址 (正常节点) [%s]: " "${MAIN_IP:-}"
    read input; [ -n "$input" ] && MAIN_IP="$input"

    printf "请输入 备用 IP 地址 (降级节点) [%s]: " "${BACKUP_IP:-}"
    read input; [ -n "$input" ] && BACKUP_IP="$input"

    printf "请输入 限速判定的带宽阈值 Mbps [%s]: " "${SPEED_THRESHOLD_MBPS:-20}"
    read input; [ -n "$input" ] && SPEED_THRESHOLD_MBPS="$input"

    cat <<EOF > "$CONFIG_FILE"
HUAWEI_AK="$(printf "%s" "$HUAWEI_AK" | tr -d '\r')"
HUAWEI_SK="$(printf "%s" "$HUAWEI_SK" | tr -d '\r')"
HUAWEI_ZONE_ID="$(printf "%s" "$HUAWEI_ZONE_ID" | tr -d '\r')"
HUAWEI_RECORDSET_ID="$(printf "%s" "$HUAWEI_RECORDSET_ID" | tr -d '\r')"
DNS_RECORD_NAME="$(printf "%s" "$DNS_RECORD_NAME" | tr -d '\r')"
MAIN_IP="$(printf "%s" "$MAIN_IP" | tr -d '\r')"
BACKUP_IP="$(printf "%s" "$BACKUP_IP" | tr -d '\r')"
SPEED_THRESHOLD_MBPS="$(printf "%s" "$SPEED_THRESHOLD_MBPS" | tr -d '\r')"
EOF

    chmod 600 "$CONFIG_FILE"
    echo "[SUCCESS] 配置已保存至 $CONFIG_FILE"
}

# 5. 华为云 DNS API 更新实现 (终极 401 修复版)
update_huawei_dns() {
    TARGET_IP="$1"
    REASON="$2"

    echo "[INFO] 准备更改 DNS 记录..."
    echo "       目标 IP : ${TARGET_IP}"
    echo "       触发原因: ${REASON}"

    # 清理参数中的 \r 回车符
    HUAWEI_AK=$(printf "%s" "$HUAWEI_AK" | tr -d '\r')
    HUAWEI_SK=$(printf "%s" "$HUAWEI_SK" | tr -d '\r')
    HUAWEI_ZONE_ID=$(printf "%s" "$HUAWEI_ZONE_ID" | tr -d '\r')
    HUAWEI_RECORDSET_ID=$(printf "%s" "$HUAWEI_RECORDSET_ID" | tr -d '\r')
    DNS_RECORD_NAME=$(printf "%s" "$DNS_RECORD_NAME" | tr -d '\r')
    TARGET_IP=$(printf "%s" "$TARGET_IP" | tr -d '\r')

    endpoint="dns.myhuaweicloud.com"
    method="PUT"
    path="/v2.1/zones/${HUAWEI_ZONE_ID}/recordsets/${HUAWEI_RECORDSET_ID}"
    url="https://${endpoint}${path}"

    body="{\"name\":\"${DNS_RECORD_NAME}\",\"type\":\"A\",\"records\":[\"${TARGET_IP}\"]}"
    x_sdk_date=$(date -u +"%Y%m%dT%H%M%SZ")

    signed_headers="content-type;host;x-sdk-date"
    body_hash=$(printf "%s" "$body" | openssl dgst -sha256 | awk '{print $2}')

    # 1. 构造 Canonical Request (用 printf '\n' 绝对保障换行符存在)
    canonical_req_str=$(printf "PUT\n%s\n\ncontent-type:application/json\nhost:%s\nx-sdk-date:%s\n\n%s\n%s" \
        "$path" "$endpoint" "$x_sdk_date" "$signed_headers" "$body_hash")

    canonical_hash=$(printf "%s" "$canonical_req_str" | openssl dgst -sha256 | awk '{print $2}')

    # 2. 构造 StringToSign
    string_to_sign=$(printf "SDK-HMAC-SHA256\n%s\n%s" "$x_sdk_date" "$canonical_hash")

    # 3. 计算签名
    signature=$(printf "%s" "$string_to_sign" | openssl dgst -sha256 -hmac "$HUAWEI_SK" | awk '{print $2}')
    authorization="SDK-HMAC-SHA256 Access=${HUAWEI_AK}, SignedHeaders=${signed_headers}, Signature=${signature}"

    # 4. 发起 API 请求
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PUT "$url" \
        -H "Content-Type: application/json" \
        -H "Host: ${endpoint}" \
        -H "X-Sdk-Date: ${x_sdk_date}" \
        -H "Authorization: ${authorization}" \
        -d "$body")

    http_code=$(echo "$response" | grep "HTTP_STATUS:" | awk -F':' '{print $2}')
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "[SUCCESS] 华为云 DNS 已成功指向: ${TARGET_IP}"
    else
        echo "[ERROR] DNS 记录更新失败，HTTP 状态码: $http_code"
        echo "$response" | sed '/HTTP_STATUS:/d'
        exit 1
    fi
}

# 6. 测速并判断切换
run_speedtest() {
    check_config_env
    echo "========================================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始探测网络带宽上限..."

    NODES_1="https://mirrors.aliyun.com/ubuntu/ls-lR.gz"
    NODES_2="https://mirrors.aliyun.com/debian/ls-lR.gz"
    NODES_3="https://mirrors.aliyun.com/centos/8-stream/isos/x86_64/CHECKSUM"
    NODES_4="https://mirrors.aliyun.com/epel/7/x86_64/Packages/a/a2ps-4.14-23.el7.x86_64.rpm"
    DURATION=3

    TMP_DIR=$(mktemp -d)

    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_1?rand=$RANDOM" > "$TMP_DIR/thread_1.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_2?rand=$RANDOM" > "$TMP_DIR/thread_2.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_3?rand=$RANDOM" > "$TMP_DIR/thread_3.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_4?rand=$RANDOM" > "$TMP_DIR/thread_4.txt" &

    wait

    TOTAL_BYTES=0
    for i in 1 2 3 4; do
        BYTES=$(cat "$TMP_DIR/thread_$i.txt" 2>/dev/null)
        [ -n "$BYTES" ] && TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
    done
    rm -rf "$TMP_DIR"

    if [ "$TOTAL_BYTES" -eq 0 ]; then
        echo "[ERROR] 测速失败，未获取到网络流量数据！"
        exit 1
    fi

    SPEED_MBPS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_BYTES * 8) / $DURATION / 1000 / 1000}")
    echo "[RESULT] 本次测得最高带宽: ${SPEED_MBPS} Mbps (判定阈值: ${SPEED_THRESHOLD_MBPS} Mbps)"

    IS_BELOW_THRESHOLD=$(awk "BEGIN {print ($SPEED_MBPS < $SPEED_THRESHOLD_MBPS) ? 1 : 0}")

    if [ "$IS_BELOW_THRESHOLD" -eq 1 ]; then
        update_huawei_dns "$BACKUP_IP" "网速处于限速状态 (${SPEED_MBPS} Mbps < ${SPEED_THRESHOLD_MBPS} Mbps)"
    else
        update_huawei_dns "$MAIN_IP" "网速正常 (${SPEED_MBPS} Mbps >= ${SPEED_THRESHOLD_MBPS} Mbps)"
    fi
}

# 7. 安装 / 卸载定时任务
manage_cron() {
    echo ""
    echo "========================================================="
    echo "                Crontab 定时任务管理"
    echo "========================================================="
    echo "1) 安装 / 替换定时任务"
    echo "2) 卸载定时任务"
    echo "0) 返回主菜单"
    echo "========================================================="
    printf "请选择 [0-2]: "
    read cron_choice

    case "$cron_choice" in
        1)
            printf "请输入定时测速的间隔分钟数 (如 5 表示每 5 分钟测速一次): "
            read MINS
            if ! echo "$MINS" | grep -qE '^[0-9]+$'; then
                echo "[ERROR] 输入无效，请输入数字！"
                return
            fi

            (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "*/$MINS * * * * /bin/sh $SCRIPT_PATH --cron >> $HOME/huawei_dns.log 2>&1") | crontab -
            echo "[SUCCESS] 已成功安装定时任务: 每 ${MINS} 分钟自动测试并切换一次！"
            echo "          运行日志文件: $HOME/huawei_dns.log"
            ;;
        2)
            crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
            echo "[SUCCESS] 已彻底移除本脚本的所有 Crontab 定时任务。"
            ;;
        *)
            return
            ;;
    esac
}

# 8. 主菜单控制系统
show_menu() {
    load_config
    while true; do
        echo ""
        echo "========================================================="
        echo "       华为云 DNS 带宽上限自动/手动检测管理脚本"
        echo "========================================================="
        echo "  1. 立即执行网速测试并自动切换 DNS"
        echo "  2. 手动强制切换为【主 IP】   (${MAIN_IP:-未配置})"
        echo "  3. 手动强制切换为【备用 IP】 (${BACKUP_IP:-未配置})"
        echo "  4. 设置 / 修改配置信息 (API 凭证、IP、阈值)"
        echo "  5. 配置 / 卸载定时任务 (Crontab)"
        echo "  0. 退出程序"
        echo "========================================================="
        printf "请输入选项 [0-5]: "
        read choice

        case "$choice" in
            1)
                run_speedtest
                ;;
            2)
                check_config_env
                update_huawei_dns "$MAIN_IP" "用户通过菜单手动切换至主 IP"
                ;;
            3)
                check_config_env
                update_huawei_dns "$BACKUP_IP" "用户通过菜单手动切换至备用 IP"
                ;;
            4)
                configure_settings
                ;;
            5)
                manage_cron
                ;;
            0)
                echo "退出程序。"
                exit 0
                ;;
            *)
                echo "[ERROR] 无效选项，请重新输入！"
                ;;
        esac
    done
}

# ----------------- 脚本主程序入口 -----------------
check_and_install_deps

if [ "$1" = "--cron" ] || [ "$1" = "--auto" ]; then
    run_speedtest
elif [ "$1" = "--force-main" ]; then
    check_config_env
    update_huawei_dns "$MAIN_IP" "命令行强制指定 --force-main"
elif [ "$1" = "--force-backup" ]; then
    check_config_env
    update_huawei_dns "$BACKUP_IP" "命令行强制指定 --force-backup"
elif [ "$1" = "--uninstall-cron" ]; then
    crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
    echo "[SUCCESS] 已通过命令行成功卸载定时任务。"
else
    show_menu
fi
