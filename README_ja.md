# Tsubame - Window Smart Mover for macOS

[English](README.md) | [日本語](README_ja.md)


![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/License-MIT-green)
![GitHub release](https://img.shields.io/github/v/release/zembutsu/tsubame)
![GitHub downloads](https://img.shields.io/github/downloads/zembutsu/tsubame/total)

macOS で複数ディスプレイを利用する時に役立つ、シンプルなウィンドウ管理（ショートカット移動・位置の記憶）ツールです。

## 開発理由・背景

ディスプレイが2画面であれば、画面を広々使えるため、様々な用途に役立ちます。この分野では　Rectangle や Magnet など、優れたツールが既に存在することは認識していましたが、敢えて「車輪の再発明」を選択しました。様々な既存ツールは多機能で素晴らしいです。しかし、私にとっては不必要であったり、各機能を使いこなすにも時間が掛かりそう。

そのため、敢えて自分でシンプルな実装を目指しました。もう10年くらい macOS アプリを作ろうと思っていましたが、毎回理解が及ばず挫折ばかり。今度こそと、問題解決に主眼を置き、あわせて SwiftUI　や　macOS　アプリ開発の理解が深まるのを目指しました。漠然としたアプリ開発に取り組むのではなく、私自身が持っている課題を解決する手段として、自ら手を動かすことで深く理解するのを目指したかったのです。ついでに、自分が欲しい機能を自分で実装できる、そういう経験も積みたかったのです。

## 主な機能

- **キーボードショートカット**: `⌃⌥⌘→/←` でウィンドウを別ディスプレイに移動
- **ディスプレイ記憶機能**: 外部ディスプレイを再接続したら自動的に元の位置に復元
- **軽量**: メニューバー常駐、リソース消費最小限
- **プライバシー重視**: すべてローカルで処理、データ送信なし

## 必要な環境

- macOS 14.0　以降
- アクセシビリティ権限 ※初回起動時に設定が必要

## インストール

1. [Releases](https://github.com/zembutsu/tsubame/releases)から最新版をダウンロード
2. `Tsubame.app` を `/Applications/` に移動
3. アプリを起動し、アクセシビリティ権限を許可

## 使い方

### ウィンドウ移動
- `⌃⌥⌘→`: 次のディスプレイへ移動
- `⌃⌥⌘←`: 前のディスプレイへ移動

### 自動復元
外部ディスプレイとの接続が切れても、再接続時、ウィンドウが自動的に元の位置に戻ります。特に、スリープモードからの復帰直後など、一時的にディスプレイが認識できない機種（私の環境）では効果が期待できます。

## 詳細

詳細な情報は英語版 [README.md](README.md) をご覧ください。

## 謝辞

このアプリは、多くの先人の開発者の皆様の成果の上に成り立っています。Rectangle や Magnet など優れたウィンドウ管理アプリを開発された方々、macOS 開発コミュニティの皆様、そしてオープンソースの知識を惜しみなく共有してくださる全ての開発者の方々に感謝いたします。

## ライセンス

MIT License

## 作者

Masahito Zembutsu ([@zembutsu](https://github.com/zembutsu))
