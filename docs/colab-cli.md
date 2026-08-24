# Google Colab を CLI から使う (colab-cli)

ローカルの `.ipynb` を Google Colab 上のノートブックと push / pull できる
コマンドラインツール [`colab-cli`](https://pypi.org/project/colab-cli/) の
セットアップ手順です。

> 注: `colab-cli` は Google 公式ではなくコミュニティ製のツールです。Google Drive
> 経由でノートブックを同期し、Colab で開きます。Google 公式の CLI が必要な場合は
> Vertex AI の Colab Enterprise (`gcloud`) を使ってください。

## 1. インストール

```bash
./tools/setup-colab-cli.sh
```

このスクリプトは `~/.colab-cli-venv` に専用の venv を作り、`colab-cli` と
`GitPython` を入れて `~/.local/bin/colab-cli` にリンクを張ります。

システムの pip に直接入れない理由:

- 依存パッケージ `pydrive` が旧式の `setup.py` 配布のため、Debian 系の
  setuptools ではビルドに失敗する (`install_layout` エラー)。venv 内の新しい
  setuptools なら PEP 517 経由でビルドできる。
- `colab-cli` は `git` (GitPython) を import するが依存に宣言していないため、
  別途インストールが必要。

確認:

```bash
colab-cli --help
```

## 2. Google API の認証情報を用意する

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
   (既存のものでも可)。
2. **APIs & Services → Library** で **Google Drive API** を有効化する。
3. **APIs & Services → OAuth consent screen** を設定する (External / テストユーザー
   に自分の Google アカウントを追加)。
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** で
   アプリケーションの種類に **Desktop app** を選び、`client_secrets.json` を
   ダウンロードする。

ダウンロードした JSON を colab-cli に登録します。

```bash
colab-cli set-config /path/to/client_secrets.json
```

**重要**: `set-config` は渡されたファイルをファイル名そのままで設定ディレクトリに
コピーするだけで、認証時に読まれるのは `client_secrets.json` という名前のファイル
だけです。別名 (`my_secrets.json` など) を渡しても `Config File set Successfully`
と表示されますが認証は通りません。必ず `client_secrets.json` にリネームしてから
渡してください。

初回のコマンド実行時にブラウザが開き、Google アカウントでの認可を求められます。

### ブラウザを開けない環境で認証する

colab-cli は PyDrive の `LocalWebserverAuth` を使い、`localhost:8080` で認可コードの
コールバックを待ち受けます。リモートコンテナや SSH 先ではこの `localhost` に手元の
ブラウザから到達できませんが、コールバックを手動で流し込めば認証を完了できます。
`tools/colab-cli-auth.sh` がこの手順を自動化します。

```bash
# 1. 認証フローを開始し、認証 URL を表示する
./tools/colab-cli-auth.sh start

# 2. 表示された URL を手元のブラウザで開いて認可する
#    → http://localhost:8080/?code=... にリダイレクトされ、接続エラーになる (正常)

# 3. URL バーの内容 (または code= の値) をそのまま渡す
./tools/colab-cli-auth.sh code 'http://localhost:8080/?code=4/0Ab...'
```

成功すると `~/.config/colab-cli/mycreds.txt` に認証情報が保存されます。

別の手段として、ローカルマシンで一度認証してから `client_secrets.json` と
`mycreds.txt` を持ち込む方法もあります。

複数の Google アカウントにログインしている場合は、使うアカウントの番号
(0 始まり) を指定します。

```bash
colab-cli set-auth-user 0
```

### 既知のハマりどころ

- `set-auth-user` は設定ディレクトリを自分では作らないため、`set-config` より先に
  実行すると `FileNotFoundError` で落ちます。`tools/setup-colab-cli.sh` は
  `~/.config/colab-cli/` を先に作るので、このスクリプトを使っていれば順序は
  問いません。
- 認可が完了すると、アクセストークンが `~/.config/colab-cli/mycreds.txt` に
  保存されます。ブラウザを開けない環境では、ローカルで一度認証してから
  `client_secrets.json` と `mycreds.txt` の 2 つを同じ場所にコピーすれば使えます。
  (`mycreds.txt` は Drive への全アクセス権を持つ認証情報なので、リポジトリには
  絶対にコミットしないでください。)

## 3. 使い方

```bash
# カレントディレクトリの .ipynb を一覧表示
colab-cli list-nb

# Colab に新しいノートブックを作成
colab-cli new-nb my_notebook.ipynb

# ローカルの .ipynb を Colab で開く (無ければアップロードして開く)
colab-cli open-nb my_notebook.ipynb

# Colab 側の内容でローカルを上書き
colab-cli pull-nb my_notebook.ipynb

# ローカルの内容で Colab 側を上書き
colab-cli push-nb my_notebook.ipynb
```

`list-nb` は再帰的に探索せず、カレントディレクトリ直下の `.ipynb` だけを
表示します。

`pull-nb` / `push-nb` は上書きなので、git で管理しているノートブックは
コミット済みの状態で実行するのが安全です。
