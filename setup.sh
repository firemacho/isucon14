#!/bin/bash

# 変数の読み込み
source config.sh

# 各サーバにおいて初期構築を実施（並行処理）
for server in "${!SERVER_HOSTS[@]}"; do
  (
    echo "Processing server with host: $server"

    # サーバに対応するホスト名を取得
    server_host="${SERVER_HOSTS[$server]}"
    if [ -z "$server_host" ]; then
      echo "Error: Unknown server '$server'"
      exit 1
    fi

    # 初期構築
    ssh "$ssh_user@$server_host" 1>/dev/null << EOF
      ## 各種インストール
      sudo apt update
      sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree
      wget -q https://github.com/tkuchiki/alp/releases/download/v1.0.9/alp_linux_amd64.zip
	    unzip alp_linux_amd64.zip
	    sudo install alp /usr/local/bin/alp
	    rm alp_linux_amd64.zip alp
      ## git初期設定
      git config --global user.email "isucon@example.com"
      git config --global user.name "isucon"
      git config --global init.defaultBranch main
      git init
      git remote add origin "$GITHUB_URL"
      ## github連携用にssh鍵を作成
      ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
EOF
  ) &
done

# すべてのバックグラウンドプロセスが終了するのを待つ
wait

# 公開鍵の表示
for server in "${!SERVER_HOSTS[@]}"; do
  server_host="${SERVER_HOSTS[$server]}"
  ssh_key=$(ssh "$ssh_user@$server_host" "cat ~/.ssh/id_ed25519.pub")
  echo "これは $server の鍵です: $ssh_key"
done

# スペックの表示
for server in "${!SERVER_HOSTS[@]}"; do
  server_host="${SERVER_HOSTS[$server]}"
  echo "---$serverのスペック---"
  ssh "$ssh_user@$server_host" 'bash -l -s' < get_system_specs.sh
done

# config.shの編集内容をリモートリポジトリに反映
git add config.sh
git commit -m "config.shのSSH設定を更新"
git push -u origin main

echo "All tasks completed."