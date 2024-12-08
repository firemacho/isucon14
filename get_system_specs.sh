#!/bin/bash

# OSの種類とバージョンを取得
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VERSION=$VERSION_ID
else
    echo "OS情報の取得に失敗しました。"
    exit 1
fi

# CPU数を取得
CPU_COUNT=$(nproc)

# メモリ数 (RAMの容量) を取得
TOTAL_MEMORY=$(free -m | awk '/^Mem:/ {print $2}') # 単位はMB

# HDDかSSDかを判定
DISK_TYPE="不明"
# メインのディスクデバイス名を取得
MAIN_DISK=$(lsblk -dno NAME,TYPE | awk '/disk/ {print $1; exit}')

if [ -n "$MAIN_DISK" ]; then
    if [[ $(cat /sys/block/$MAIN_DISK/queue/rotational) -eq 0 ]]; then
        DISK_TYPE="SSD"
    else
        DISK_TYPE="HDD"
    fi
fi

# MySQLのバージョンを取得
if command -v mysql >/dev/null 2>&1; then
    MYSQL_VERSION=$(mysql --version | cut -d' ' -f2-)
else
    MYSQL_VERSION="未インストール"
fi

# Nginxのバージョンを取得
if command -v nginx >/dev/null 2>&1; then
    NGINX_VERSION=$(nginx -v 2>&1 | cut -d' ' -f3-)
else
    NGINX_VERSION="未インストール"
fi

# Goのバージョンを取得
if command -v go >/dev/null 2>&1; then
    GO_VERSION=$(go version | cut -d' ' -f3)
else
    GO_VERSION="未インストール"
fi

# 結果を表示
echo "OSの種類: $OS"
echo "OSのバージョン: $VERSION"
echo "CPU数: $CPU_COUNT"
echo "メモリ数 (MB): $TOTAL_MEMORY"
echo "ストレージタイプ: $DISK_TYPE"
echo "MySQLのバージョン: $MYSQL_VERSION"
echo "Nginxのバージョン: $NGINX_VERSION"
echo "goのバージョン: $GO_VERSION"