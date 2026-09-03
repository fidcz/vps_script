#!/bin/sh

# =========================================================
# 带宽峰值探测 & 华为云 DNS 自动双向切换脚本 (纯原生 Shell)
# =========================================================

# ----------------- 用户配置变量 -----------------
SPEED_THRESHOLD_MBPS=20         # 触发阈值 (Mbps)
MAIN_IP="1.1.1.1"               # 主 IP (网速正常/大于等于20Mbps时使用)
BACKUP_IP="2.2.2.2"             # 备用 IP (网速受限/低于20Mbps时使用)

# 华为云 API 参数
HUAWEI_AK="你的HUAWEI_AK"
HUAWEI_SK="你的HUAWEI_SK"
HUAWEI_ZONE_ID="ff8080829ffb1be501a064d68398469a"
HUAWEI_RECORDSET_ID="ff8080829ffaffa101a064d826650b61"
DNS_RECORD_NAME="example.com."  # 域名记录名称 (注意末尾保留半角点号)

# 测速节点池 (阿里云镜像站)
NODES_1="https://mirrors.aliyun.com/ubuntu/ls-lR.gz"
NODES_2="https://mirrors.aliyun.com/debian/ls-lR.gz"
NODES_3="https://mirrors.aliyun.com/centos/8-stream/isos/x86_64/CHECKSUM"
NODES_4="https://mirrors.aliyun.com/epel/7/x86_64/Packages/a/a2ps-4.14-23.el7.x86_64.rpm"

THREADS=4
DURATION=3
# -------------------------------------------------

# 1. 自动检测系统并补齐缺失依赖
check_and_install_deps() {
    MISSING_CMDS=""
    for cmd in curl openssl awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_CMDS="$MISSING_CMDS $cmd"
        fi
    done

    if [ -n "$MISSING_CMDS" ]; then
        echo "[INFO] 检测到缺失必要工具:$MISSING_CMDS，正在尝试自动安装..."
        
        # 识别系统包管理器并安装
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y -qq curl openssl gawk
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y -q curl openssl gawk
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y -q curl openssl gawk
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add --no-cache curl openssl gawk
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -Sy --noconfirm curl openssl gawk
        elif command -v opkg >/dev/null 2>&1; then
            opkg update && opkg install curl openssl-util gawk
        else
            echo "[ERROR] 未能识别当前系统的包管理器，请手动安装:$MISSING_CMDS"
            exit 1
        fi
        echo "[INFO] 依赖工具安装完成！"
    fi
}

# HMAC-SHA256 签名辅助函数
sha256_hex() { printf "%s" "$1" | openssl dgst -sha256 | awk '{print $2}'; }
hmac_sha256_hex() { printf "%s" "$2" | openssl dgst -sha256 -hmac "$1" | awk '{print $2}'; }

# 华为云 DNS 修改 API
update_huawei_dns() {
    TARGET_IP="$1"
    REASON="$2"

    echo "[INFO] 开始切换 DNS，目标 IP: ${TARGET_IP} (原因: ${REASON})"

    endpoint="dns.myhuaweicloud.com"
    method="PUT"
    path="/v2.1/zones/${HUAWEI_ZONE_ID}/recordsets/${HUAWEI_RECORDSET_ID}"
    url="https://${endpoint}${path}"

    body="{\"name\":\"${DNS_RECORD_NAME}\",\"type\":\"A\",\"records\":[\"${TARGET_IP}\"]}"
    x_sdk_date=$(date -u +"%Y%m%dT%H%M%SZ")

    canonical_headers="content-type:application/json\nhost:${endpoint}\nx-sdk-date:${x_sdk_date}\n"
    signed_headers="content-type;host;x-sdk-date"
    body_hash=$(sha256_hex "$body")

    canonical_request="${method}\n${path}/\n\n${canonical_headers}\n${signed_headers}\n${body_hash}"
    canonical_hash=$(sha256_hex "$canonical_request")

    string_to_sign="SDK-HMAC-SHA256\n${x_sdk_date}\n${canonical_hash}"
    signature=$(hmac_sha256_hex "$HUAWEI_SK" "$string_to_sign")
    authorization="SDK-HMAC-SHA256 Access=${HUAWEI_AK}, SignedHeaders=${signed_headers}, Signature=${signature}"

    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X PUT "$url" \
        -H "Content-Type: application/json" \
        -H "Host: ${endpoint}" \
        -H "X-Sdk-Date: ${x_sdk_date}" \
        -H "Authorization: ${authorization}" \
        -d "$body")

    http_code=$(echo "$response" | grep "HTTP_STATUS:" | awk -F':' '{print $2}')
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo "[SUCCESS] 华为云 DNS 记录成功更新为 ${TARGET_IP}"
    else
        echo "[ERROR] DNS 记录更新失败，HTTP 状态码: $http_code"
        echo "$response" | sed '/HTTP_STATUS:/d'
        exit 1
    fi
}

# 执行测速逻辑
run_speedtest() {
    echo "========================================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始网络带宽上限探测..."

    TMP_DIR=$(mktemp -d)

    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_1?rand=$RANDOM" > "$TMP_DIR/thread_1.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_2?rand=$RANDOM" > "$TMP_DIR/thread_2.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_3?rand=$RANDOM" > "$TMP_DIR/thread_3.txt" &
    curl -s -w "%{size_download}" -o /dev/null -m $DURATION "$NODES_4?rand=$RANDOM" > "$TMP_DIR/thread_4.txt" &

    wait

    TOTAL_BYTES=0
    for i in 1 2 3 4; do
        BYTES=$(cat "$TMP_DIR/thread_$i.txt" 2>/dev/null)
        if [ -n "$BYTES" ]; then
            TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
        fi
    done
    rm -rf "$TMP_DIR"

    if [ "$TOTAL_BYTES" -eq 0 ]; then
        echo "[ERROR] 测速失败，未获取到流量数据！"
        exit 1
    fi

    SPEED_MBPS=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_BYTES * 8) / $DURATION / 1000 / 1000}")
    echo "[RESULT] 本次测得最高带宽: ${SPEED_MBPS} Mbps (阈值: ${SPEED_THRESHOLD_MBPS} Mbps)"

    IS_BELOW_THRESHOLD=$(awk "BEGIN {print ($SPEED_MBPS < $SPEED_THRESHOLD_MBPS) ? 1 : 0}")

    if [ "$IS_BELOW_THRESHOLD" -eq 1 ]; then
        update_huawei_dns "$BACKUP_IP" "网速低于 ${SPEED_THRESHOLD_MBPS} Mbps"
    else
        update_huawei_dns "$MAIN_IP" "网速正常 (${SPEED_MBPS} Mbps >= ${SPEED_THRESHOLD_MBPS} Mbps)"
    fi
}

# ----------------- 主程序入口 -----------------
check_and_install_deps

case "$1" in
    --force-main)
        echo "[MODE] 触发强制模式：直接切换至【主 IP】"
        update_huawei_dns "$MAIN_IP" "命令行强制指定 --force-main"
        ;;
    --force-backup)
        echo "[MODE] 触发强制模式：直接切换至【备用 IP】"
        update_huawei_dns "$BACKUP_IP" "命令行强制指定 --force-backup"
        ;;
    *)
        run_speedtest
        ;;
esac
