# BusTimeTable (iOS)

個人用のバス時刻表アプリ（SwiftUI）です。  
指定した1路線の時刻表を JSON で管理し、**次のバス表示 / 到着予定表示 / 通知 / ウィジェット** を使えるようにしています。

## 主な機能（第一段階）
- 今日のダイヤ種別を自動判定
  - 平日
  - 土曜
  - 日曜・祝日（`holidays.json` を参照）
- 次のバスを複数件表示
  - 発車時刻
  - 到着予定時刻
  - あと何分
- 特定の出発時刻をプルダウンで確認
- **ローカル通知**
  - 選択した便の5分前に通知
  - 設定/解除のトグル対応
- **ホーム画面ウィジェット**
  - 次のバス3便を表示

---

## プロジェクト構成
```bash:構成図
構成図
BusTimeTable/
├─ BusTimeTable.xcodeproj
├─ BusTimeTable/
│  ├─ BusTimeTableApp.swift
│  ├─ ContentView.swift
│  ├─ BusCore.swift              # App / Widget 共通ロジック
│  ├─ Assets.xcassets
│  ├─ times.json                 # バスの種別と時刻表（Git管理外）
│  ├─ holidays.json              # 祝日一覧
│  └─ ...
├─ BusTimeTableWidget.swiftExtension/
│  ├─ BusTimeTableWidget.swift
│  ├─ BusTimeTableWidget_swiftBundle.swift
│  └─ ...
└─ README.md
```

---

## 注意点
### times.json を作成する（必須）

このリポジトリでは個人用時刻データを含むため times.json を Git 管理から外しています。
利用の際には、以下 dammytimes.json の記法に従って先述のプロジェクト構成通りに times.json を配置してください。

#### `dammytimes.json`
```
{
  "routeName": "サンプル路線",
  "stopName": "サンプル停留所",
  "weekday": {
    "outbound": [
      { "depart": "07:00", "arrive": "07:20" },
      { "depart": "07:15", "arrive": "07:35" },
      { "depart": "07:30", "arrive": "07:50" },
      { "depart": "08:00", "arrive": "08:20" }
    ]
  },
  "saturday": {
    "outbound": [
      { "depart": "07:10", "arrive": "07:30" },
      { "depart": "07:40", "arrive": "08:00" },
      { "depart": "08:10", "arrive": "08:30" }
    ]
  },
  "sundayHoliday": {
    "outbound": [
      { "depart": "07:20", "arrive": "07:40" },
      { "depart": "08:00", "arrive": "08:20" },
      { "depart": "08:40", "arrive": "09:00" }
    ]
  }
}
```
