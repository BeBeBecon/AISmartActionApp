import Foundation

// MARK: - Prompt Factory
// ----------------------------------
// AIに送信するプロンプト（指示文）を生成するための専門クラス
// プロンプトのテンプレートを一元管理することで、メンテナンス性を向上させる
// ----------------------------------
struct PromptFactory {
    
    /// 【ステップ2用】テキスト要約・校正プロンプトを生成する
    static func createSummarizePrompt(for text: String) -> String {
        return """
        あなたは優秀なエディターです。以下のテキストに含まれる誤字脱字を修正し、内容を論理的に整理して、要点をまとめた簡潔な文章にしてください。
        特に、日付、時刻、場所、人名、連絡先などの重要な情報が分かりやすくなるようにしてください。
        
        【重要】日付と時刻の表記について:
        - 日付は必ず「YYYY年M月D日」の形式で統一してください
        - 時刻は必ず「HH:MM」の24時間表記で統一してください
        - 曜日がある場合は「(月)」「(火)」のように括弧付きで表記してください
        - 例: 2025年10月15日(火) 14:30
        
        【最重要】
        応答には、修正・要約された文章本体のみを出力し、それ以外の説明や前置きは絶対に含めないでください。

        ---
        【元のテキスト】
        \(text)
        ---
        """
    }
    
    /// 【ステップ3用】アクション抽出プロンプトを生成する
    static func createActionGenerationPrompt(for summary: String) -> String {
        // AIが日付を正しく解釈できるよう、現在の日時情報をプロンプトに含める
        let now = Date()
        let calendar = Calendar.current
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年M月d日(E)"
        dateFormatter.locale = Locale(identifier: "ja_JP")
        let currentDateString = dateFormatter.string(from: now)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTimeString = timeFormatter.string(from: now)
        
        let weekday = calendar.component(.weekday, from: now)
        let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]
        let currentWeekday = weekdayNames[weekday - 1]

        return """
        あなたは優秀なアシスタントです。

        【あなたのタスク】
        以下の【要約されたテキスト】から情報を抽出し、【出力形式】に厳密に従ってアクションを提案してください。
        アクションが見つからない場合は、何も出力しないでください。
        イベント名や人名は、【出力例】のサンプルではなく、必ず【要約されたテキスト】から抽出した具体的な名称を使用してください。

        【現在の日時情報】
        - 今日の日付: \(currentDateString)
        - 今日は\(currentWeekday)曜日です
        - 現在の時刻: \(currentTimeString)

        【重要】日付と時刻の処理ルール：
        1. 過去の日付も未来の日付も、書かれている通りに解釈してください。
        2. 相対的な日付（今日, 明日, 来週など）は【現在の日時情報】を基準に絶対的な日付に変換してください。
        3. 終了時刻が不明な場合は、開始時刻の1時間後を終了時刻として設定してください。
        4. 日付の出力は、必ず YYYY-MM-DDTHH:mm の形式にしてください。

        【重要】カレンダー登録のルール：
        - イベント名は「場所: イベントの概要」という形式で出力してください。
        - 例: 「東京チャペル: 挙式」

        【出力例】（これはあくまでフォーマットの例です。内容はテキストに合わせてください）
        - 「来週火曜14時から15時にかけて、青山カンファレンスセンターで新製品の打ち合わせ」 → カレンダー登録: 青山カンファレンスセンター: 新製品の打ち合わせ; 2025-10-14T14:00; 2025-10-14T15:00
        - 「吉田さんの携帯: 080-9999-8888」 → 連絡先登録: 吉田さん, 080-9999-8888,

        【出力形式】（必ず行頭に「- 」をつけてください）
        - カレンダー登録: [場所: イベント名]; [開始日時 YYYY-MM-DDTHH:mm]; [終了日時 YYYY-MM-DDTHH:mm]
        - 経路検索: [テキストから抽出した住所や場所名]
        - 連絡先登録: [テキストから抽出した氏名], [電話番号], [メールアドレス]
        - URLを開く: [URL]
        - 電話をかける: [電話番号]
        - メモに追加: [メモのタイトルとして適切な、テキスト冒頭の短い文]

        ---
        【要約されたテキスト】
        \(summary)
        ---
        """
    }
}

