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

        ---
        \(text)
        ---
        """
    }
    
    /// 【ステップ3用】アクション抽出プロンプトを生成する
    static func createActionGenerationPrompt(for summary: String) -> String {
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
        
        【現在の日時情報】
        - 今日の日付: \(currentDateString)
        - 今日は\(currentWeekday)曜日です
        - 現在の時刻: \(currentTimeString)
        
        以下の要約されたテキストから情報を抽出し、具体的なアクションを提案してください。
        
        【重要】日付と時刻の処理ルール：
        1. 相対的な日付の変換:
           - 「今日」→ \(currentDateString)
           - 「明日」→ 今日の翌日
           - 「明後日」→ 今日の2日後
           - 「来週〇曜日」→ 次の週の該当曜日
           - 「再来週〇曜日」→ 2週間後の該当曜日
        
        2. 時刻の処理:
           - 「午前」「AM」→ 0:00-11:59
           - 「午後」「PM」→ 12:00-23:59
           - 「正午」→ 12:00
           - 「夕方」→ 17:00
           - 「夜」→ 19:00
           - 時刻が不明な場合→ 10:00
        
        3. 日付のみで時刻が不明な場合:
           - 「〇月〇日」のみ → その日の10:00
           - 文脈から業務時間と推測される → 10:00
           - 文脈から夕方と推測される → 17:00
        
        4. 出力フォーマット:
           必ず YYYY-MM-DDTHH:mm の形式で出力してください
        
        【出力例】
        現在が2025年10月7日(月)の場合:
        - 「明日の午後3時に会議」 → カレンダー登録: 会議; 2025-10-08T15:00
        - 「来週火曜日の打ち合わせ」 → カレンダー登録: 打ち合わせ; 2025-10-14T10:00
        - 「10月15日午前9時 ミーティング」 → カレンダー登録: ミーティング; 2025-10-15T09:00
        - 「10月20日」 → カレンダー登録: (イベント名); 2025-10-20T10:00

        【出力形式】（必ず行頭に「- 」をつけてください）
        - カレンダー登録: [イベント名]; [YYYY-MM-DDTHH:mm]
        - 経路検索: [住所や場所名]
        - 連絡先登録: [氏名], [電話番号], [メールアドレス]
        - URLを開く: [URL]
        - 電話をかける: [電話番号]

        ---
        【要約されたテキスト】
        \(summary)
        ---
        """
    }

    /// 【チャット用】カレンダーイベント調整プロンプトを生成する
    static func createChatPrompt(action: ProposedAction, conversationHistory: [ChatMessage], userInput: String) -> String {
        let dateString: String
        if let date = action.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
            formatter.locale = Locale(identifier: "ja_JP")
            dateString = formatter.string(from: date)
        } else {
            dateString = "日時未設定"
        }
        
        // dropLast()でユーザーの最新メッセージは除外する
        let history = conversationHistory.dropLast().map { msg in
            "\(msg.role == .user ? "ユーザー" : "AI"): \(msg.content)"
        }.joined(separator: "\n")

        return """
        あなたは優秀なアシスタントです。ユーザーがカレンダーイベントの内容を調整したいと考えています。
        
        現在のイベント情報:
        - イベント名: \(action.value)
        - 日時: \(dateString)
        
        これまでの会話:
        \(history)
        
        ユーザーの最新の要望: \(userInput)
        
        【あなたのタスク】
        1. ユーザーの要望を理解し、どのように変更すべきか判断する
        2. 変更後の内容を明確に説明する
        3. 最後に、以下の形式で変更内容を出力する（必ず含めてください）:
        
        [変更内容]
        イベント名: [新しいイベント名]
        日時: [YYYY-MM-DDTHH:mm形式の日時]
        
        注意: 日時の変更がない場合は元の日時を、イベント名の変更がない場合は元のイベント名をそのまま記載してください。
        """
    }
}
