# 変数定義 ------------------------

# 問題によって変わる変数
ENV_FILE:=env.sh # DB接続情報が記されているファイル
include $(ENV_FILE) # DB接続情報およびSERVER_ID(セットアップ時に追記)の読み込み

USER:=isucon
BIN_NAME:=isucondition # ビルドにより作成する実行ファイル名
BUILD_DIR:=/home/isucon/webapp/go # go buildを実行するディレクトリ
SERVICE_NAME:=isucondition.go.service
GO_PATH:=/home/isucon/local/go/bin/go #which goの結果

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

NGINX_LOG:=/var/log/nginx/access.log
DB_SLOW_LOG:=/var/log/mysql/mysql-slow.log

WEBHOOK_URL="https://discord.com/api/webhooks/1315115211459526727/FzBuKpdrzTNzDBYIK9H5fT8O1ZEyU0bh_c5dhK1_UDDJiF3A3ALNPwqBhPfPwLKXAFJy"

# メインで使うコマンド ------------------------

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id get-db-conf get-nginx-conf get-service-file get-envsh

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-nginx-conf deploy-service-file deploy-envsh

# ログローテ及びリポジトリの内容をサーバに反映する
## 全サービスを一括でrestartしてしまうので本来不要なサービスまで起動することに注意
.PHONY: apply
apply: check-server-id mv-logs build deploy-conf restart

# DBに接続する
.PHONY: access-db
access-db:
	mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)

# slow queryを確認する
.PHONY: slow-query
slow-query:
	sudo pt-query-digest $(DB_SLOW_LOG)

# alpでアクセスログを確認する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=/home/isucon/tool-config/alp/config.yml

# pprofのCPUプロファイル結果を確認する
.PHONY: pprof
pprof:
	$(GO_PATH) tool pprof -cum -top ~/logs/pprof/cpu.prof

# pprofのWebUIを起動する
.PHONY: start-pprof
start-pprof:
	$(GO_PATH) tool pprof -http=localhost:8090 logs/pprof/cpu.prof &

# pprofのWebUIを停止する
## pprofのバイナリファイルを実行しているプロセスを検出してkillする
.PHONY: kill-pprof
kill-pprof:
	@pprof_pid=$(shell pgrep -f "/pprof -http=localhost:8090" | grep -v $$$$); \
	if [ -n "$$pprof_pid" ]; then \
		kill $$pprof_pid; \
	fi

# pprofの呼び出し相関図の作成
.PHONY: pprof-png
pprof-png:
	$(GO_PATH) tool pprof -png ~/logs/pprof/cpu.prof > $(PNG_OUTPUT_PATH)

# 主要コマンドの構成要素 ------------------------

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s1" >> $(ENV_FILE)

.PHONY: set-as-s2
set-as-s2:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s2" >> $(ENV_FILE)

.PHONY: set-as-s3
set-as-s3:
	echo "" >> $(ENV_FILE)
	echo "SERVER_ID=s3" >> $(ENV_FILE)

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	sudo chown $(USER) ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/$(ENV_FILE) ~/$(SERVER_ID)/home/isucon/$(ENV_FILE)

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp ~/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	cp ~/$(SERVER_ID)/home/isucon/$(ENV_FILE) ~/$(ENV_FILE)

.PHONY: build
build:
	cd $(BUILD_DIR); \
	$(GO_PATH) build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)
	sudo systemctl restart mysql
	sudo systemctl restart nginx

.PHONY: daemon-reload
daemon-reload:
	sudo systemctl daemon-reload

.PHONY: stop
stop:
	sudo systemctl stop nginx
	output=$$(sudo systemctl disable nginx 2>&1) || echo "$$output"
	sudo systemctl stop $(SERVICE_NAME)
	output=$$(sudo systemctl disable $(SERVICE_NAME) 2>&1) || echo "$$output"
	sudo systemctl stop mysql
	output=$$(sudo systemctl disable mysql 2>&1) || echo "$$output"
# disableコマンドが正常終了した場合は標準エラー出力を表示しない

.PHONY: start-app
start-app:
	output=$$(sudo systemctl enable $(SERVICE_NAME) 2>&1) || echo "$$output"
	sudo systemctl start $(SERVICE_NAME)

.PHONY: start-mysql
start-mysql:
	output=$$(sudo systemctl enable mysql 2>&1) || echo "$$output"
	sudo systemctl start mysql	

.PHONY: start-nginx
start-nginx:
	output=$$(sudo systemctl enable nginx 2>&1) || echo "$$output"
	sudo systemctl start nginx

# ログローテをし、2世代よりも古いログは削除（ディスクフル対策）
.PHONY: mv-logs
mv-logs:
	$(eval TIMESTAMP := $(shell date -u -d "+9 hours" "+%Y%m%d_%H%M%S"))
	sudo test -f $(NGINX_LOG) && \
		mkdir -p ~/logs/nginx && \
		sudo mv -f $(NGINX_LOG) ~/logs/nginx/access.log_$(TIMESTAMP) || echo""
	sudo test -f $(DB_SLOW_LOG) && \
		mkdir -p ~/logs/mysql && \
		sudo mv -f $(DB_SLOW_LOG) ~/logs/mysql/mysql-slow.log_$(TIMESTAMP) || echo ""
	sudo test -f ~/logs/pprof/cpu.prof && \
	    mkdir -p ~/logs/pprof && \
	    sudo mv -f ~/logs/pprof/cpu.prof ~/logs/pprof/cpu.prof_$(TIMESTAMP) || echo ""
	ls ~/logs/nginx/access.log_* > /dev/null 2>&1 && ls -1tr ~/logs/nginx/access.log_* | head -n -2 | xargs -d '\n' rm -f -- || echo "No log files to remove in: ~/logs/nginx"
	ls ~/logs/mysql/mysql-slow.log_* > /dev/null 2>&1 && ls -1tr ~/logs/mysql/mysql-slow.log_* | head -n -2 | xargs -d '\n' rm -f -- || echo "No log files to remove in: ~/logs/mysql"
	ls ~/logs/pprof/cpu.prof_* > /dev/null 2>&1 && ls -1tr ~/logs/pprof/cpu.prof_* | head -n -2 | xargs -d '\n' rm -f -- || echo "No log files to remove in: ~/logs/pprof"

.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

.PHONY: post_discord
post_discord:
	@curl -sS -H "Content-Type: multipart/form-data" -X POST \
	-F "file=@$(file)" \
	-F "username=isucon-server" \
	"$(WEBHOOK_URL)"
