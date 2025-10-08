import Foundation
import FoundationModels

// MARK: - LLM Service
// ----------------------------------
// Foundation Models (LLM) とのやり取りを専門に担当するクラス
// プロンプトの構築、AIへのリクエスト、応答の解析などを行う
// ----------------------------------
class LLMService {
    
    /// AIとの対話セッションを管理するインスタンス
    private let session = LanguageModelSession()
    
    /// テキストをAIに要約・校正させる
    func summarizeText(_ text: String) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else {
            throw LLMError.modelNotAvailable
        }
        
        let prompt = PromptFactory.createSummarizePrompt(for: text)
        var summary = ""
        let stream = try await session.streamResponse(to: prompt)
        for try await response in stream {
            summary = response.content
        }
        return summary
    }
    
    /// 要約テキストからアクションを生成・解析する
    func generateActions(from summary: String) async throws -> (rawOutput: String, actions: [ProposedAction]) {
        guard SystemLanguageModel.default.availability == .available else {
            throw LLMError.modelNotAvailable
        }
        
        let prompt = PromptFactory.createActionGenerationPrompt(for: summary)
        var rawOutput = ""
        let stream = try await session.streamResponse(to: prompt)
        for try await response in stream {
            rawOutput = response.content
        }
        
        let actions = parseLLMOutput(rawOutput)
        return (rawOutput, actions)
    }

    /// 対話を通じてカレンダーイベントを調整する
    func adjustCalendarEvent(action: ProposedAction, conversationHistory: [ChatMessage], userInput: String) async throws -> (response: String, updatedAction: ProposedAction) {
        guard SystemLanguageModel.default.availability == .available else {
            throw LLMError.modelNotAvailable
        }
        
        let prompt = PromptFactory.createChatPrompt(
            action: action,
            conversationHistory: conversationHistory,
            userInput: userInput
        )
        
        var response = ""
        let stream = try await session.streamResponse(to: prompt)
        for try await chunk in stream {
            response = chunk.content
        }
        
        let updatedAction = updateActionFromAIResponse(response, originalAction: action)
        return (response, updatedAction)
    }
    
    /// LLMからの文字列出力を解析して、アクションのリストに変換する
    private func parseLLMOutput(_ output: String) -> [ProposedAction] {
        var actions: [ProposedAction] = []
        let lines = output.split(separator: "\n")
        
        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            
            // 行頭の「- 」を考慮したパース
            if lineStr.contains("カレンダー登録:") {
                let cleaned = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                let components = cleaned.replacingOccurrences(of: "カレンダー登録:", with: "").components(separatedBy: ";")
                
                let title = components.first?.trimmingCharacters(in: .whitespaces) ?? ""
                var date: Date? = nil
                
                if components.count > 1 {
                    let dateString = components[1].trimmingCharacters(in: .whitespaces)
                    date = DateParser.parseDate(from: dateString)
                    if date == nil { print("⚠️ [Parser] 日付のパースに失敗: '\(dateString)'") }
                }
                if !title.isEmpty {
                    actions.append(ProposedAction(type: .addCalendarEvent, value: title, date: date))
                }
                
            } else if lineStr.contains("経路検索:") {
                let value = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "経路検索:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    actions.append(ProposedAction(type: .searchMap, value: value))
                }
                
            } else if lineStr.contains("連絡先登録:") {
                let contactInfo = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "連絡先登録:", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let name = contactInfo.indices.contains(0) ? contactInfo[0] : ""
                let phone = contactInfo.indices.contains(1) ? contactInfo[1] : nil
                let email = contactInfo.indices.contains(2) ? contactInfo[2] : nil
                if !name.isEmpty {
                    actions.append(ProposedAction(type: .addContact, value: name, secondaryValue: phone, tertiaryValue: email))
                }
                
            } else if lineStr.contains("URLを開く:") {
                let value = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "URLを開く:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    actions.append(ProposedAction(type: .openURL, value: value))
                }
                
            } else if lineStr.contains("電話をかける:") {
                let value = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "電話をかける:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    actions.append(ProposedAction(type: .call, value: value))
                }
            }
        }
        return actions
    }
    
    /// AIの応答から変更内容を抽出し、アクションを更新する
    private func updateActionFromAIResponse(_ response: String, originalAction: ProposedAction) -> ProposedAction {
        var action = originalAction
        
        if let changeStart = response.range(of: "[変更内容]") {
            let changeSection = String(response[changeStart.upperBound...])
            let lines = changeSection.split(separator: "\n")
            
            for line in lines {
                let lineStr = String(line).trimmingCharacters(in: .whitespaces)
                
                if lineStr.hasPrefix("イベント名:") {
                    let newTitle = lineStr.replacingOccurrences(of: "イベント名:", with: "").trimmingCharacters(in: .whitespaces)
                    if !newTitle.isEmpty { action.value = newTitle }
                }
                
                if lineStr.hasPrefix("日時:") {
                    let dateString = lineStr.replacingOccurrences(of: "日時:", with: "").trimmingCharacters(in: .whitespaces)
                    if let date = DateParser.parseDate(from: dateString) {
                        action.date = date
                    }
                }
            }
        }
        return action
    }

    /// LLM関連のエラーを定義
    enum LLMError: Error {
        case modelNotAvailable
    }
}


// MARK: - Date Parser
// ----------------------------------
// 様々な形式の日付文字列をDateオブジェクトに変換するヘルパークラス
// ----------------------------------
struct DateParser {
    
    static func parseDate(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let japanTimeZone = TimeZone(identifier: "Asia/Tokyo") else { return nil }
        
        // 試行する日付フォーマットのリスト
        let formatters: [DateFormatter] = [
            {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = japanTimeZone
                return formatter
            }(),
            {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/MM/dd HH:mm"
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.timeZone = japanTimeZone
                return formatter
            }(),
            {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy年M月d日 HH:mm"
                formatter.locale = Locale(identifier: "ja_JP")
                formatter.timeZone = japanTimeZone
                return formatter
            }(),
            {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = japanTimeZone
                return formatter
            }()
        ]
        
        // 各フォーマットを順番に試す
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                // 日付のみのフォーマットの場合、デフォルトで10:00を設定
                if formatter.dateFormat == "yyyy-MM-dd" {
                    var calendar = Calendar.current
                    calendar.timeZone = japanTimeZone
                    return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)
                }
                return date
            }
        }
        return nil
    }
}
