# AutoFisher-VRC

VRChat world **FISH!** 向け自動釣りツールの開発リポジトリです。

## 現在の構成

実行基盤には `day123123123/vrc-auto-fish` release `26031901` の自己完結EXEを使用し、
公式の `patch/` ローダーで AutoFisher-VRC 側のコードを優先読込します。

白バー制御は `TheRealShieri/VRCAutoFisher` の予測制御思想を基準に再設計しています。

## 通常UI

通常利用で表示するものは次の4項目だけです。

- VRChat接続状態
- 自動釣り状態
- 釣果数
- 開始/停止 + Debug

Hotkey:

- `F9` — 開始 / 停止
- `F10` — 停止
- `F11` — Debug表示

## UIから除外した機能

通常利用には不要なため、次の機能はGUIから除外しています。

- パラメータ手動調整
- プリセット
- ROI設定
- スクリーンショット
- 魚ホワイトリスト設定
- 統計ダイアログ
- YOLOデバイス設定
- YOLO学習用データ収集
- 言語切替
- 防スタック方式/時間調整
- ログ表示/クリア
- IL録画/学習操作

内部のFISH!検出、YOLO、状態機械、入力、安全停止処理は維持します。

## Canonical patch

```text
patch/
├─ core/
│  ├─ pd_controller.py
│  ├─ control_executor.py
│  └─ control_backends.py
└─ gui/
   └─ app.py
```

day123本体の約2GB配布物はこのリポジトリには含めません。
