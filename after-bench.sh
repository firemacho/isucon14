#!/bin/bash

# 変数の読み込み
source config.sh

# サーバ名が指定されているか確認
if [ "$#" -eq 0 ]; then
  echo "Error: No server names or 'all' provided"
  echo "Usage: $0 [-b branch] s1 s2 ... | all"
  exit 1
fi

# 引数が all の場合、すべてのサーバ名を対象とする
if [ "$1" = "all" ]; then
  set -- "${!SERVER_HOSTS[@]}"
fi

# 各サーバにて解析を実施（並行処理）
for server in "$@"; do
  (
    # サーバに対応するホスト名を取得
    server_host="${SERVER_HOSTS[$server]}"
    if [ -z "$server_host" ]; then
      echo "Error: Unknown server '$server'"
      exit 1
    fi

    # サーバに対応するサービスを取得し、空白で分割
    IFS=' ' read -ra services <<< "${SERVER_SERVICES[$server]}"

    # 解析の実施
    for service in "${services[@]}"; do
      case "$service" in
        "app")
          echo "Analyzing cpu.pprof on server '$server'"
          ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
            ## CPUプロファイル結果の作成
            make pprof > /tmp/$server-cpu-pprof.txt
            make post_discord file=/tmp/$server-cpu-pprof.txt
            ## 呼び出し相関図の作成
            make pprof-png PNG_OUTPUT_PATH=/tmp/$server-cpu-pprof.png
            make post_discord file=/tmp/$server-cpu-pprof.png
            ## WebUIの起動
            make start-pprof > /dev/null 2>&1 
EOF
          ;;

        "nginx")
          echo "Analyzing Nginx log on server '$server'"
          ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
            make alp > /tmp/$server-alp.txt
            make post_discord file=/tmp/$server-alp.txt
EOF
          ;;

        "mysql")
          echo "Analyzing slow-query log on server '$server'"
          ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
            make slow-query > /tmp/$server-slow-query.txt
            make post_discord file=/tmp/$server-slow-query.txt
EOF
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