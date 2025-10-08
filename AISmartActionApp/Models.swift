import Foundation

// MARK: - ProposedAction
// ----------------------------------
// LLMからの提案を構造化して扱うためのデータ型
// ----------------------------------
struct ProposedAction: Hashable, Identifiable {
    let id = UUID()
    var type: ActionType
    var value: String          // メインの値 (イベント名、場所など)
    var secondaryValue: String?  // 補助的な値 (電話番号など)
    var tertiaryValue: String?   // 補助的な値その2 (メールアドレス、メモなど)
    var date: Date?            // 開始日時
    var endDate: Date?         // 終了日時
    
    init(type: ActionType, value: String, secondaryValue: String? = nil, tertiaryValue: String? = nil, date: Date? = nil, endDate: Date? = nil) {
        self.type = type
        self.value = value
        self.secondaryValue = secondaryValue
        self.tertiaryValue = tertiaryValue
        self.date = date
        self.endDate = endDate
    }
    
    enum ActionType: String {
        case addCalendarEvent = "カレンダー登録"
        case searchMap = "経路検索"
        case addContact = "連絡先登録"
        case openURL = "URLを開く"
        case call = "電話をかける"
        case addNote = "メモに追加"
        case unknown = "不明"
    }
    
    var systemImageName: String {
        switch type {
        case .addCalendarEvent: "calendar.badge.plus"
        case .searchMap: "map.fill"
        case .addContact: "person.crop.circle.badge.plus"
        case .openURL: "safari.fill"
        case .call: "phone.fill"
        case .addNote: "note.text.badge.plus"
        case .unknown: "questionmark.circle"
        }
    }
}

