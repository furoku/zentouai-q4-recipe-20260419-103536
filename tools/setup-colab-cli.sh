#!/usr/bin/env bash
# colab-cli (https://pypi.org/project/colab-cli/) をこの環境で使えるようにする。
#
# システムの pip へ直接入れると、依存の pydrive が古い setup.py のまま配布
# されているためビルドに失敗する。専用の venv を作り、そこへ入れてから
# ~/.local/bin へシンボリックリンクを張る。
set -euo pipefail

VENV="${COLAB_CLI_VENV:-$HOME/.colab-cli-venv}"
BIN_DIR="${COLAB_CLI_BIN_DIR:-$HOME/.local/bin}"

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip setuptools wheel
# GitPython は colab-cli が import するが、依存に宣言されていないので明示的に入れる。
"$VENV/bin/pip" install colab-cli GitPython

mkdir -p "$BIN_DIR"
ln -sf "$VENV/bin/colab-cli" "$BIN_DIR/colab-cli"

"$BIN_DIR/colab-cli" --help >/dev/null
echo "colab-cli を $BIN_DIR/colab-cli にインストールしました。"
echo "PATH に $BIN_DIR が含まれていることを確認してください。"
