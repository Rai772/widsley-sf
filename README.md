# widsley-sf

SalesforceにリードがインポートされるとApexトリガーが自動発火し、リードを6パターンに自動判定・ルーティングするシステム。

## アーキテクチャ

```
比較媒体からリード取得（lead-scraper）
　↓
全件SFに登録
　↓
LeadTrigger（after insert）
　↓
LeadTriggerHandler → LeadFilterService
　├─ 既存顧客   → IsExistingCustomer__c=true → SFフローでCSへSlack通知
　├─ 重複       → 新リードをアーカイブ・既存リード備考追記
　├─ 再流入     → 新リードをアーカイブ・既存リード備考追記
　├─ いたずら   → Status=アーカイブ・first_touchpoint__c更新
　├─ 逆営業     → Status=アーカイブ・first_touchpoint__c更新（未実装）
　└─ 有効リード → 変更なし（既存SFフローでMQL通知）
```

## ディレクトリ構成

```
widsley-sf/
├── force-app/main/default/
│   ├── classes/
│   │   ├── LeadFilterService.cls        ✅ 判定ロジック
│   │   ├── LeadFilterServiceTest.cls    ✅ テスト
│   │   ├── LeadTriggerHandler.cls       ✅ トリガーハンドラ
│   │   ├── LeadTriggerHandlerTest.cls   ✅ テスト
│   │   └── MockHttpResponse.cls        ✅ テスト用モック
│   └── triggers/
│       └── LeadTrigger.trigger          ✅ リード登録時に発火
└── sfdx-project.json
```

## セットアップ

### 1. 前提条件

- Salesforce CLI (`sf`) インストール済み
- Cursor / VSCode + Salesforce Extension Pack インストール済み

### 2. SF組織と接続

```bash
sf org login web --alias widsley-prod
```

### 3. ソースコードをSFに反映

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/LeadFilterService.cls \
  --source-dir force-app/main/default/classes/LeadFilterServiceTest.cls \
  --source-dir force-app/main/default/classes/LeadTriggerHandler.cls \
  --source-dir force-app/main/default/classes/LeadTriggerHandlerTest.cls \
  --source-dir force-app/main/default/classes/MockHttpResponse.cls \
  --source-dir force-app/main/default/triggers/LeadTrigger.trigger \
  --target-org widsley-prod \
  --test-level RunSpecifiedTests \
  --tests LeadFilterServiceTest \
  --tests LeadTriggerHandlerTest
```

## 判定ロジック

### 判定順序

チェックは上から順に実行し、該当した時点で後続チェックはスキップする。

| 順序 | パターン | 判定条件 |
|------|---------|---------|
| ① | 既存顧客 | 取引先責任者を照合し、紐づく契約の`churn_status__c`が空欄 |
| ② | 重複 | 同一メール or 電話のリードが存在し`LeadSourceDate__c`が半年以内 |
| ③ | 再流入 | 同一メール or 電話のリードが存在し`LeadSourceDate__c`が半年超 |
| ④ | いたずら | 電話番号が10桁未満 or 11桁超 |
| ⑤ | 逆営業 | 問い合わせ内容にキーワードを含む（🔴 未実装） |
| ⑥ | 有効リード | 上記①〜⑤のいずれにも該当しない |

### 各パターンのSF処理

#### 既存顧客
- `IsExistingCustomer__c = true` をセット
- SFフロー「CSリード通知」が`#CSリードチャンネル`にSlack通知

#### 重複 / 再流入
- 新しいリードの`Status = アーカイブ`
- 既存リードの`Remarks__c`に追記（例：`重複より再問い合わせあり（2026-05-13）`）

#### いたずら
- `Status = アーカイブ`
- `first_touchpoint__c` を以下の値に更新

| 媒体 | 値 |
|------|---|
| アスピック | `アスピック（逆営業と無効）` |
| ミツモア | `ミツモア（逆営業と無効）` |
| アイミツSaaS | `アイミツSaaS（逆営業と無効）` |
| その他 | `逆営業と無効` |

#### 有効リード
- 変更なし（既存SFフロー「リードのSlack通知」でMQL通知）

## SFカスタムフィールド

### リードオブジェクト

| フィールド | API参照名 | 説明 |
|-----------|----------|------|
| 既存顧客フラグ | `IsExistingCustomer__c` | 既存顧客判定時にtrueをセット |
| 初回流入経路 | `first_touchpoint__c` | いたずら/逆営業時に更新 |
| 備考 | `Remarks__c` | 重複/再流入時に追記 |
| 初回流入日 | `LeadSourceDate__c` | 重複/再流入の半年判定に使用 |

### 契約オブジェクト（Contract__c）

| フィールド | API参照名 | 説明 |
|-----------|----------|------|
| 取引先名 | `AccountId__c` | 取引先との紐づけ |
| 解約ステータス | `churn_status__c` | 空欄=成約中と判定 |

## SFフロー

| フロー名 | トリガー | 説明 |
|---------|---------|------|
| CSリード通知 | リード作成時（`IsExistingCustomer__c = true`） | #CSリードチャンネルへ通知 |

## 今後の実装予定

| Phase | 内容 | 状態 |
|-------|------|------|
| Phase 4 | 逆営業チェック | 🔴 キーワードリスト待ち |

## 関連リポジトリ

- [lead-scraper](https://github.com/Rai772/lead-scraper) - 比較媒体からリードを取得してSFに登録するRPAツール