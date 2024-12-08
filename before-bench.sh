#!/bin/bash

# 変数の読み込み
source config.sh

# オプションの解析
while getopts "b:" opt; do
  case $opt in
    b)
      branch="$OPTARG"
      ;;
    *)
      echo "Usage: $0 [-b branch] s1 s2 ... | all"
      exit 1
      ;;
  esac
done

# オプション以外の引数を処理
shift $((OPTIND-1))

# サーバ名が指定されているか確認
if [ "$#" -eq 0 ]; then
  echo "Error: No server names or 'all' provided"
  echo "Usage: $0 [-b branch] s1 s2 ... | all"
  exit 1
fi

# ブランチ名が指定されているか確認
if [ -z "$branch" ]; then
  echo "Error: No branch name provided"
  echo "Usage: $0 [-b branch] s1 s2 ... | all"
  exit 1
fi

# 引数が all の場合、すべてのサーバ名を対象とする
if [ "$1" = "all" ]; then
  set -- "${!SERVER_HOSTS[@]}"
fi

# 各サーバに対してブランチを適用（並行処理）
for server in "$@"; do
  (
    # サーバに対応するホスト名を取得
    server_host="${SERVER_HOSTS[$server]}"
    if [ -z "$server_host" ]; then
      echo "Error: Unknown server '$server'"
      exit 1
    fi

    # /配下のディスク使用量が90%を超えている場合は警告を表示
    THRESHOLD=90
    USAGE=$(ssh $ssh_user@$server_host df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ $USAGE -ge $THRESHOLD ]; then
      echo "Disk usage on / is above ${THRESHOLD}% on ${HOST}. Current usage is ${USAGE}%."
    fi

    # サーバに対応するサービスを取得し、空白で分割
    IFS=' ' read -ra services <<< "${SERVER_SERVICES[$server]}"

    # サーバでブランチをチェックアウト
    echo "Checkout branch '$branch' on server '$server'"
    ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
      git fetch

      ## origin/$branchが無い時はエラー
      git rev-parse --verify "origin/$branch" > /dev/null 2>&1
      if [ \$? -ne 0 ]; then
        echo "Error: branch 'origin/$branch' does not exist." >&2
        exit 1
      fi

      ## "$branch"をチェックアウト（既存の最新化もしくは新規作成）
      git show-ref --verify --quiet refs/heads/"$branch"
      if [ \$? -eq 0 ]; then
        git checkout "$branch"
        git merge --ff-only "origin/$branch"
      else
        git checkout -b "$branch" "origin/$branch"
      fi
EOF
    if [ $? -ne 0 ]; then
      echo "Error occurred during remote operations"
      exit 1
    fi

    # ブランチの内容を適用
    echo "Stop services, lotate logs, and deploy files on server '$server'"
    ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
      ## 各サービスの停止
      make check-server-id stop kill-pprof
      ## ログローテ・ビルド・設定ファイルの配置
      make mv-logs build deploy-conf daemon-reload
EOF

    # サービスの起動
    for service in "${services[@]}"; do
      case "$service" in
        "app")
          echo "Starting app on server '$server'"
          ssh "$ssh_user@$server_host" "make start-app 1>/dev/null" 2> >(while read line; do echo "[$server] $line"; done)
          ;;

        "nginx")
          echo "Starting Nginx on server '$server'"
          ssh "$ssh_user@$server_host" "make start-nginx 1>/dev/null" 2> >(while read line; do echo "[$server] $line"; done)
          ;;

        "mysql")
          echo "Starting MySQL on server '$server'"
          ssh "$ssh_user@$server_host" "make start-mysql 1>/dev/null" 2> >(while read line; do echo "[$server] $line"; done)
          ;;

        *)
          echo "Error: Unknown service for server '$server'"
          ;;
      esac
    done
  ) &
done

# すべてのバックグラウンドプロセスが終了するのを待つ
wait
echo "All tasks completed."