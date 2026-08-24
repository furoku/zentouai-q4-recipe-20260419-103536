#!/usr/bin/env bash
# ブラウザを開けない環境 (リモートコンテナ / SSH 先など) で colab-cli の
# OAuth 認証を通すためのヘルパー。
#
# colab-cli は PyDrive の LocalWebserverAuth を使う。これは localhost:8080 で
# コールバックを待ち受けるため、手元のブラウザからは到達できない。そこで
#   1. `start` でフローを開始し、認証 URL を表示する
#   2. 手元のブラウザでその URL を開いて認可する
#   3. リダイレクト先 (http://localhost:8080/?code=... 接続エラーになる) の
#      URL バーから code= の値をコピーする
#   4. `code <値>` でこの環境のコールバックサーバに流し込む
# という手順で認証を完了させる。
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/colab-cli"
STATE_DIR="${COLAB_CLI_AUTH_STATE_DIR:-${TMPDIR:-/tmp}/colab-cli-auth}"
LOG="$STATE_DIR/flow.log"
PORT="${COLAB_CLI_AUTH_PORT:-8080}"

usage() {
  cat <<'USAGE'
使い方:
  colab-cli-auth.sh start [<ipynb>]  認証フローを開始し、認証 URL を表示する
  colab-cli-auth.sh code <CODE>      ブラウザで得た認可コードを流し込む
  colab-cli-auth.sh status           フローのログを表示する
USAGE
}

require_config() {
  if [[ ! -f "$CONFIG_DIR/client_secrets.json" ]]; then
    echo "エラー: $CONFIG_DIR/client_secrets.json がありません。" >&2
    echo "  colab-cli set-config /path/to/client_secrets.json を先に実行してください。" >&2
    exit 1
  fi
  if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
    echo "エラー: auth user が未設定です。colab-cli set-auth-user 0 を実行してください。" >&2
    exit 1
  fi
}

cmd_start() {
  require_config
  local nb="${1:-}"
  mkdir -p "$STATE_DIR"
  rm -f "$LOG"

  if [[ -z "$nb" ]]; then
    # 認証だけを走らせたいときのための使い捨てノートブック。
    nb="$STATE_DIR/_auth_probe.ipynb"
    printf '{"cells":[],"metadata":{},"nbformat":4,"nbformat_minor":5}' > "$nb"
    ( cd "$STATE_DIR" && git rev-parse --git-dir >/dev/null 2>&1 || git init -q . )
    nb="_auth_probe.ipynb"
  fi

  ( cd "$STATE_DIR" && nohup colab-cli open-nb "$nb" > "$LOG" 2>&1 & )

  local url=""
  for _ in $(seq 1 30); do
    url="$(grep -o 'https://accounts\.google\.com/o/oauth2/auth?[^ ]*' "$LOG" 2>/dev/null | head -1 || true)"
    [[ -n "$url" ]] && break
    sleep 1
  done

  if [[ -z "$url" ]]; then
    echo "認証 URL を取得できませんでした。ログ:" >&2
    cat "$LOG" >&2
    exit 1
  fi

  cat <<MSG

次の URL をブラウザで開いて認可してください:

$url

認可後、ブラウザは http://localhost:$PORT/?code=... へリダイレクトします
(この環境の localhost なので接続エラーになりますが、それで正常です)。
URL バーの code= の値をコピーして、次を実行してください:

  $0 code '<コピーした code の値>'

MSG
}

cmd_code() {
  local code="${1:-}"
  if [[ -z "$code" ]]; then
    echo "エラー: 認可コードを指定してください。" >&2
    exit 1
  fi
  # ブラウザから丸ごとコピーされた URL を渡された場合も拾えるようにする。
  if [[ "$code" == *"code="* ]]; then
    code="${code#*code=}"
    code="${code%%&*}"
  fi

  curl -s -m 15 --get --data-urlencode "code=$code" "http://localhost:$PORT/" >/dev/null

  # 交換結果がログに出るまで少し待つ。
  sleep 5
  if [[ -f "$CONFIG_DIR/mycreds.txt" ]]; then
    echo "認証に成功しました。認証情報を $CONFIG_DIR/mycreds.txt に保存しました。"
  else
    echo "認証に失敗した可能性があります。ログ:" >&2
    tail -20 "$LOG" >&2
    exit 1
  fi
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  code)   shift; cmd_code "$@" ;;
  status) tail -40 "$LOG" ;;
  *)      usage; exit 1 ;;
esac
