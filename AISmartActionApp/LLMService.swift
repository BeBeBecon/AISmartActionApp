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
    
    /// LLMからの文字列出力を解析して、アクションのリストに変換する
    private func parseLLMOutput(_ output: String) -> [ProposedAction] {
        var actions: [ProposedAction] = []
        let lines = output.split(separator: "\n")
        
        for line in lines {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            
            if lineStr.contains("カレンダー登録:") {
                let cleaned = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                let components = cleaned.replacingOccurrences(of: "カレンダー登録:", with: "").components(separatedBy: ";")
                
                let title = components.first?.trimmingCharacters(in: .whitespaces) ?? ""
                var startDate: Date? = nil
                var endDate: Date? = nil
                
                if components.count > 1 {
                    let startDateString = components[1].trimmingCharacters(in: .whitespaces)
                    startDate = DateParser.parseDate(from: startDateString)
                    if startDate == nil { print("⚠️ [Parser] 開始日時のパースに失敗: '\(startDateString)'") }
                }

                if components.count > 2 {
                    let endDateString = components[2].trimmingCharacters(in: .whitespaces)
                    endDate = DateParser.parseDate(from: endDateString)
                    if endDate == nil { print("⚠️ [Parser] 終了日時のパースに失敗: '\(endDateString)'") }
                }

                if !title.isEmpty {
                    actions.append(ProposedAction(type: .addCalendarEvent, value: title, date: startDate, endDate: endDate))
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
            } else if lineStr.contains("メモに追加:") {
                let value = lineStr.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "メモに追加:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    actions.append(ProposedAction(type: .addNote, value: value))
                }
            }
        }
        return actions
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
        
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
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

