#!/usr/bin/env bash
set -euo pipefail

# 環境変数から設定ファイルを生成します。
# 例:
#   AWS_PROD_ACCOUNT="123456789012"
#   AWS_DEV_ACCOUNT="999999999999"
#   AWS_ADMIN_MATCH="Admin,Administrator"
#   AWS_DEV_MATCH="Dev,Developer"
#   AWS_RO_MATCH="ReadOnly,Read-Only,RO"

python3 - <<'PY'
import json
import os
import re


def split_list(value):
    if not value:
        return []
    parts = re.split(r"[\s,]+", value.strip())
    return [p for p in parts if p]

config = {
    "prodAccounts": split_list(os.getenv("AWS_PROD_ACCOUNT", "")),
    "devAccounts": split_list(os.getenv("AWS_DEV_ACCOUNT", "")),
    "roleRules": [
        {
            "name": "Administrator",
            "match": split_list(os.getenv("AWS_ADMIN_MATCH", "Admin,Administrator")),
            "color": "#DC2626",
        },
        {
            "name": "Developer",
            "match": split_list(os.getenv("AWS_DEV_MATCH", "Dev,Developer")),
            "color": "#2563EB",
        },
        {
            "name": "ReadOnly",
            "match": split_list(os.getenv("AWS_RO_MATCH", "ReadOnly,Read-Only,RO")),
            "color": "#6B7280",
        },
    ],
    "envColors": {
        "Prod": "#F59E0B",
        "Dev": "#2563EB",
        "Unknown": "#64748B",
    },
}

with open("config.local.json", "w", encoding="utf-8") as f:
    json.dump(config, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

echo "config.local.json を作成しました。"
