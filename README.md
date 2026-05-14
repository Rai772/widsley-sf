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
　├─ 重複       → 新リードをアーカイブ・既存リード/取引先責任者の備考追記・Slack通知
　├─ 再流入     → 新リードをアーカイブ・既存リード/取引先責任者の備考追記・Slack通知
　├─ いたずら   → Status=アーカイブ・first_touchpoint__c更新
　├─ 逆営業     → Status=アーカイブ・first_touchpoint__c更新（未実装）
　└─ 有効リード → 自動取引開始（取引先・取引先責任者を新規作成）・MQL通知
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
│   │   ├── LeadConvertService.cls       ✅ 有効リード自動取引開始
│   │   ├── LeadConvertServiceTest.cls   ✅ テスト
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
sf project deploy start --source-dir force-app/main/default/classes/LeadFilterService.cls --source-dir force-app/main/default/classes/LeadFilterServiceTest.cls --source-dir force-app/main/default/classes/LeadTriggerHandler.cls --source-dir force-app/main/default/classes/LeadTriggerHandlerTest.cls --source-dir force-app/main/default/classes/LeadConvertService.cls --source-dir force-app/main/default/classes/LeadConvertServiceTest.cls --source-dir force-app/main/default/classes/MockHttpResponse.cls --source-dir force-app/main/default/triggers/LeadTrigger.trigger --target-org widsley-prod --test-level RunSpecifiedTests --tests LeadFilterServiceTest --tests LeadTriggerHandlerTest --tests LeadConvertServiceTest
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

#### 重複
- 新しいリードの`Status = アーカイブ`
- 既存リードの`IsDuplicate__c = true`をセット
- 既存リード or 取引先責任者の`Remarks__c`に追記
- SFフロー「重複リード通知」がSlack通知

追記フォーマット：
```
{新リードのDescription}
{新リードのweb__c}
{first_touchpoint__c}より重複問い合わせあり（日付）
```

#### 再流入
- 新しいリードの`Status = アーカイブ`
- 新リードの`IsReflow__c = true`・`ReflowSourceLeadId__c`に既存リードIDをセット
- 既存リード or 取引先責任者の`Remarks__c`に追記・`IsReflow__c = true`をセット
- SFフロー「再流入リード通知」がSlack通知

追記フォーマット：
```
{新リードのDescription}
{新リードのweb__c}
{first_touchpoint__c}より再流入問い合わせあり（日付）
```

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
- `LeadConvertService`により自動取引開始
  - 取引先（Account）：新規作成
  - 取引先責任者（Contact）：新規作成
  - 商談：作成しない
  - 取引開始状況：`商談化`
  - 所有者：Widsley Admin
- 既存SFフロー「リードのSlack通知」でMQL通知

## SFカスタムフィールド

### リードオブジェクト

| フィールド | API参照名 | 説明 |
|-----------|----------|------|
| 既存顧客 | `IsExistingCustomer__c` | 既存顧客判定時にtrueをセット |
| 初回流入経路 | `first_touchpoint__c` | いたずら/逆営業時に更新 |
| 備考 | `Remarks__c` | 重複/再流入時に追記 |
| 初回流入日 | `LeadSourceDate__c` | 重複/再流入の半年判定に使用 |
| 再流入あり | `IsReflow__c` | 再流入判定時にtrueをセット |
| 既存リードID | `ReflowSourceLeadId__c` | 再流入時に既存リードのIDをセット |
| 重複あり | `IsDuplicate__c` | 重複判定時にtrueをセット |
| セールス担当 | `User__c` | 取引開始時の所有者 |

### 取引先責任者オブジェクト

| フィールド | API参照名 | 説明 |
|-----------|----------|------|
| 再流入あり | `IsReflow__c` | 再流入判定時にtrueをセット |
| 重複あり | `IsDuplicate__c` | 重複判定時にtrueをセット |

### 契約オブジェクト（Contract__c）

| フィールド | API参照名 | 説明 |
|-----------|----------|------|
| 取引先名 | `AccountId__c` | 取引先との紐づけ |
| 解約ステータス | `churn_status__c` | 空欄=成約中と判定 |
| 元商談 | `first_oppotunity__c` | 紐づく商談 |

## SFフロー

| フロー名 | トリガー | 通知先 | 説明 |
|---------|---------|--------|------|
| CSリード通知 | リード作成時（`IsExistingCustomer__c = true`） | #CSリードチャンネル | 既存顧客からの問い合わせ通知 |
| リードのSlack通知 | リード作成時 | 既存チャンネル | MQL通知 |
| 重複リード通知 | リード更新時（`IsDuplicate__c = true`） | 既存チャンネル | 重複リード通知 |
| 重複リード通知（取引先責任者） | 取引先責任者更新時（`IsDuplicate__c = true`） | 既存チャンネル | 取引先責任者ありの重複通知 |
| 再流入リード通知 | リード更新時（`IsReflow__c = true`） | 既存チャンネル | 既存リードありの再流入通知 |
| 再流入リード通知（取引先責任者） | 取引先責任者更新時（`IsReflow__c = true`） | 既存チャンネル | 取引先責任者ありの再流入通知 |

## 今後の実装予定

| Phase | 内容 | 状態 |
|-------|------|------|
| Phase 4 | 逆営業チェック | 🔴 キーワードリスト待ち |

## 関連リポジトリ

- [lead-scraper](https://github.com/Rai772/lead-scraper) - 比較媒体からリードを取得してSFに登録するRPAツール