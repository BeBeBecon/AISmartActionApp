import Foundation

// MARK: - ProposedAction
// ----------------------------------
// LLMからの提案を構造化して扱うためのデータ型
// ----------------------------------
struct ProposedAction: Hashable, Identifiable { // Identifiableに準拠
    let id = UUID() // リスト表示のためにユニークなIDを追加
    var type: ActionType
    var value: String // チャット中に更新可能にするため var に変更
    var secondaryValue: String? // チャット中に更新可能にするため var に変更
    var tertiaryValue: String? // チャット中に更新可能にするため var に変更
    var date: Date? // チャット中に更新可能にするため var に変更
    
    init(type: ActionType, value: String, secondaryValue: String? = nil, tertiaryValue: String? = nil, date: Date? = nil) {
        self.type = type
        self.value = value
        self.secondaryValue = secondaryValue
        self.tertiaryValue = tertiaryValue
        self.date = date
    }
    
    // ActionTypeとsystemImageNameは変更なし
    enum ActionType: String {
        case addCalendarEvent = "カレンダー登録"
        case searchMap = "経路検索"
        case addContact = "連絡先登録"
        case openURL = "URLを開く"
        case call = "電話をかける"
        case unknown = "不明"
    }
    
    var systemImageName: String {
        switch type {
        case .addCalendarEvent: "calendar.badge.plus"
        case .searchMap: "map.fill"
        case .addContact: "person.crop.circle.badge.plus"
        case .openURL: "safari.fill"
        case .call: "phone.fill"
        case .unknown: "questionmark.circle"
        }
    }
}


// MARK: - ChatMessage
// ----------------------------------
// AIとのチャットのやり取りを管理するためのデータ構造
// ----------------------------------
struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatRole // 発言者がユーザーなのかAIなのか
    let content: String // 発言内容
    
    enum ChatRole {
        case user  // ユーザーからのメッセージ
        case model // AIからの応答
    }
}
