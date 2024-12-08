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

    # topを20秒おきに4回実行
    (
      TOP_FILE_PATH="/tmp/$server-top.txt"
      ITERATIONS=4
      echo "Execute top on server '$server'"
      sleep 10
      for ((i = 0; i < ITERATIONS; i++));  do
        ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
          top -1 -b -n 1 | head -n 20 > ${TOP_FILE_PATH}
          make post_discord file=${TOP_FILE_PATH}
EOF
        if ((i < ITERATIONS - 1)); then
          sleep 20
        fi
      done
    ) &

    # 並行して、90秒間cpu.profを取得
    if [[ " ${services[@]} " =~ " app " ]]; then
      (
        echo "Get cpu.prof on server '$server'"
        ssh -T "$ssh_user@$server_host" 2> >(while read line; do echo "[$server] $line"; done) 1>/dev/null << EOF
          mkdir -p ~/logs/pprof
          curl -sS http://localhost:6060/debug/pprof/profile?second=90 > ~/logs/pprof/cpu.prof
EOF
      ) &
    fi
    
    # forループ内で実行したすべてのバックグラウンドプロセスが終了するのを待つ
    wait
  ) &
done

# すべてのバックグラウンドプロセスが終了するのを待つ
wait
echo "All tasks completed."