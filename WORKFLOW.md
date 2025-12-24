# WORKFLOW.md - Bebop Style Development Session Guide

> Version: 0.2.2 (S004で更新)
> Purpose: 人間とAIのセッション開始/終了手順を明確化

---

## Document Hierarchy

セッション開始時に読む順序:

```
1. 直前のセッションログ (Sxxx_SESSION-LOG-*.md)
   └── Handoff Bridge が最重要
   
2. WORKFLOW.md (このファイル)
   └── セッションの進め方
   
3. ARCHITECTURE.md
   └── コード構造、行番号マップ
   └── ※現時点の上位概念。新概念が出たら相対的に後退
   
4. Bebop Style Development 定義 (zip/リポジトリ)
   └── 記録スタイル、用語定義
   └── 必要に応じて参照
```

---

## Session Start Checklist

### For Human (Zem)

```markdown
□ 1. 直前セッションログをClaudeに提供
     - Handoff Bridge の Must Read ファイル
     - 未merge PR/branch があれば状態共有
     
□ 2. 今日のゴールを宣言
     - Primary: 必ずやること
     - Secondary: 時間があれば
     
□ 3. 前回のParkedを確認
     - Issue化するか
     - 今日やるか
     - 引き続きParkか
```

### For AI (Claude)

```markdown
□ 0. ファイル添付確認（最初に実行）
     - WORKFLOW.md がなければ「ローカルのWORKFLOW.mdをアップロードしてください」と指示
     - ARCHITECTURE.md がなければ同様に指示
     - 直前セッションログがなければ確認
     - ※これらが揃うまで作業を開始しない

□ 1. Handoff Bridge を読む
     - Must Read のファイルを確認
     - Warnings を把握
     - Carry Forward のタスク確認
     
□ 2. ARCHITECTURE.md を確認
     - 行番号マップで目的の箇所を特定
     - viewは最小限に
     
□ 3. スコープ確認を人間に返す
     - 理解した内容を要約
     - 不明点を質問
     - 推奨アプローチを提案
```

---

## Session Flow

```
[Session Start]
     │
     ▼
┌─────────────────────────────┐
│ 1. Context Restore          │
│    - Read Handoff Bridge    │
│    - Check Parked items     │
└─────────────────────────────┘
     │
     ▼
┌─────────────────────────────┐
│ 2. Scope Agreement          │
│    - Primary/Secondary定義  │
│    - 判断ポイント予測       │
└─────────────────────────────┘
     │
     ▼
┌─────────────────────────────┐
│ 3. Implementation           │
│    - Path記録しながら進行   │
│    - 判断ポイントで確認     │
└─────────────────────────────┘
     │
     ▼
┌─────────────────────────────┐
│ 4. Checkpoint (適宜)        │
│    - commit単位で区切り     │
│    - 動作確認               │
└─────────────────────────────┘
     │
     ▼
┌─────────────────────────────┐
│ 5. Session Wrap-up          │
│    - Parked処理             │
│    - ARCHITECTURE.md更新    │
│    - Handoff Bridge作成     │
│    - セッションログ出力     │
└─────────────────────────────┘
```

---

## AI Autonomy Scope

### 自律判断OK（確認不要）

| 領域 | 例 |
|------|-----|
| ファイル分割/統合 | 大きすぎるファイルを分割 |
| 関数名/変数名 | 命名規則に従った命名 |
| エラーハンドリング | guard/try-catch追加 |
| ログ出力レベル | debugPrint/verbosePrint選択 |
| ドキュメント作成タイミング | 実装前/後の判断 |
| リファクタリング提案 | 改善案の提示 |

### 確認必須（人間に聞く）

| 領域 | 例 |
|------|-----|
| 新規依存関係 | ライブラリ追加 |
| 既存APIの変更 | 公開メソッドのシグネチャ変更 |
| ユーザー向けデフォルト値 | 新機能のデフォルトON/OFF |
| セキュリティ/プライバシー | ログ出力内容、データ保存 |
| Issue/PRの作成 | 何を分けるか |
| スコープ拡大 | 当初予定外の作業 |

---

## Parked Management

### Parked発生時

```markdown
1. セッションログのParkedセクションに追加
2. 優先度を判定（高/中/低）
3. 行き先を決定:
   - 新規Issue → 独立したタスク
   - 次セッション → 継続作業
   - 振り返りセッション → プロセス改善
```

### セッション終了時のParkedチェック

```markdown
□ Parkedが3つ以上 → Issue化を検討
□ 同じ項目が2セッション以上Park → 必ずIssue化
□ 高優先度のParked → 次セッションのPrimaryに
```

---

## Handoff Bridge Template

```markdown
### 次のセッション (Sxxx)

**ターゲット**: [1行で目標]

| タスク | 説明 |
|--------|------|
| ... | ... |

### Must Read
- [前回セッションログ]
- [ARCHITECTURE.md] ← 更新があれば
- [関連Issue/PR]

### Carry Forward
- [ ] タスク1
- [ ] タスク2

### Warnings
- [注意事項]

### Open Issues
| # | Title | Type |
|---|-------|------|
| ... | ... | ... |
```

---

## Recording Conventions

### Path記録

```markdown
├── Sxxx-a [HH:MM] タスク名
│   ├── 作業内容1
│   ├── 作業内容2
│   └── <distance: 0.xx>
```

### 判断ポイント記録

```markdown
│   ├── ★ 判断ポイント: [何を決めたか]
│   │   ├── 選択肢A: [内容]
│   │   ├── 選択肢B: [内容] → 採用 ★
│   │   └── 理由: [なぜBを選んだか]
```

### Language Policy

| 対象 | 言語 |
|------|------|
| Issue title/body | English |
| PR title/body | English |
| Commit message | English |
| Code comments | English |
| セッションログ | 日本語OK（プロジェクト言語） |
| WORKFLOW.md等 | 日本語OK |

---

## Document Maintenance

### ARCHITECTURE.md 更新タイミング

**AIの責務**: 以下の変更を行った場合、セッション終了前にARCHITECTURE.mdを更新する

- 新しいファイル追加時 → File Structure、Singleton Managers更新
- 大きな構造変更時 → 該当セクション更新
- 行番号が大幅にずれた時 → Line Number Map更新
- 新しいUserDefaultsキー追加時 → Settings Architecture更新
- 新しいData Flow追加時 → Data Flow更新
- Known Issues発見時 → Known Issues / Technical Debt更新

### PROJECT.md 更新タイミング

**AIの責務**: セッション終了時に以下を確認し、必要に応じて更新する

- バージョン番号が変わった時 → Current Status更新
- リリースが完了した時 → Roadmap Completed更新
- 新しいIssueが計画に入った時 → Roadmap Planned更新
- 開発方針が変わった時 → Development Principles更新

### WORKFLOW.md 更新タイミング

- プロセス改善提案があった時
- 振り返りセッションで決定した時

---

## Anti-Patterns

### ❌ やってはいけないこと

| パターン | 問題 | 対策 |
|----------|------|------|
| Handoff Bridgeなしで終了 | 次回コンテキスト喪失 | 必ず作成 |
| Parked放置 | 忘却 | 3セッションでIssue化 |
| 大ファイル全体をview | トークン浪費 | ARCHITECTURE.md参照 |
| 確認なしでスコープ拡大 | 時間超過 | 必ず相談 |
| ログにアプリ名出力 | プライバシー | マスク化 |

---

## Quick Reference

### セッション開始の一言目（Human）

```
前回のセッションログです。[ファイル添付]
今日は [Primary] をやりたい。Parkedの [項目] も確認したい。
```

### セッション開始の返答（AI）

```
Handoff Bridge確認しました。
- Must Read: [確認したファイル]
- Carry Forward: [残タスク]
- Warnings: [注意事項]

今日のスコープ:
- Primary: [内容]
- Secondary: [内容]

開始しますか？
```

---

## Document Information

- Version: 0.2.2
- Created: 2025-12-22 (S003)
- Updated: 2025-12-24 (S004) - Language Policy追加、AIファイル確認チェック追加、ARCHITECTURE.md更新責務明記、PROJECT.md更新責務追加
- Author: Claude (AI) with Zem
- Next Review: S005 or after 3 sessions
