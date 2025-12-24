# AWS 環境リボン（個人利用）

## 目的
AWS コンソールの左上に、環境（Prod / Dev）と権限（ReadOnly / Developer / Administrator）をリボン表示します。

## 事前準備
アカウントIDはリポジトリにコミットしないため、環境変数から `config.local.json` を生成します。

```
cd ./aws_chrome_extension
export AWS_PROD_ACCOUNT="123456789012"
export AWS_DEV_ACCOUNT="999999999999"
./setup_config.sh
```

## インストール（Chrome 拡張の読み込み）
1. Chromeで `chrome://extensions` を開く
2. 右上の「デベロッパーモード」をオン
3. 「パッケージ化されていない拡張機能を読み込む」
4. `aws_chrome_extension` ディレクトリを選択

## 表示ロジック
- アカウントIDが `prodAccounts` に含まれていれば `Prod`
- アカウントIDが `devAccounts` に含まれていれば `Dev`
- 権限はロール名/ユーザー名に文字列が含まれているかで判定

### 判定ルールのカスタマイズ
`setup_config.sh` の環境変数で調整できます。

```
export AWS_ADMIN_MATCH="Admin,Administrator,PowerUser"
export AWS_DEV_MATCH="Dev,Developer"
export AWS_RO_MATCH="ReadOnly,Read-Only,RO"
./setup_config.sh
```

## トラブルシュート
- 表示されない場合は、AWS コンソール画面をリロードしてください。
- それでも表示されない場合は、アカウントメニュー周辺のDOM構造変更が原因の可能性があります。
  `content.js` の `SELECTORS` を環境に合わせて調整してください。
