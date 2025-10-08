import UIKit
import SwiftUI

// MARK: - Action Execution Service
// ----------------------------------
// 提案されたアクション（カレンダー登録、経路検索など）を実行する専門クラス
// Viewからアプリ連携の具体的なロジックを分離する
// ----------------------------------
class ActionExecutionService {
    
    // サービスへのアクセスを容易にするためのインスタンス
    private let calendarService = CalendarService()
    private let contactsService = ContactsService()

    /// どのアクションを実行するかを決定し、適切なメソッドを呼び出す
    func execute(_ action: ProposedAction) {
        // ---------------------------------------------------------
        // ▼ 他アプリを起動するための「命令」としてのインテント ▼
        // ---------------------------------------------------------
        switch action.type {
        case .addCalendarEvent:
            executeCalendarAction(action)
        case .addContact:
            executeAddContactAction(action)
        case .searchMap:
            executeSearchMapAction(action)
        case .openURL:
            executeOpenURLAction(action)
        case .call:
            executeCallAction(action)
        case .unknown:
            print("⚠️ 不明なアクションです。")
        }
    }
    
    // 画面の最前面にあるViewControllerを取得するためのヘルパー
    private var rootViewController: UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("⚠️ エラー: ViewControllerの取得に失敗しました")
            return nil
        }
        return rootVC
    }

    /// カレンダー登録処理を実行する
    private func executeCalendarAction(_ action: ProposedAction) {
        // チャットシートが閉じるアニメーションと競合しないように、わずかに遅延させて実行する
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let vc = self.rootViewController else { return }
            print("📅 カレンダー登録を実行: \(action.value)")
            if let date = action.date {
                print("   日時: \(date)")
            } else {
                print("   ⚠️ 警告: 日時が設定されていません")
            }
                    
            self.calendarService.addEvent(title: action.value, date: action.date, from: vc)
        }
    }

    /// 連絡先登録処理を実行する
    private func executeAddContactAction(_ action: ProposedAction) {
        guard let vc = rootViewController else { return }
        contactsService.addContact(name: action.value, phone: action.secondaryValue, email: action.tertiaryValue, from: vc)
    }
    
    /// マップでの経路検索を実行する
    private func executeSearchMapAction(_ action: ProposedAction) {
        guard let query = action.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        // Googleマップアプリがインストールされていれば優先的に使用
        if let googleMapsUrl = URL(string: "comgooglemaps://?q=\(query)"), UIApplication.shared.canOpenURL(googleMapsUrl) {
            UIApplication.shared.open(googleMapsUrl)
        } else if let appleMapsUrl = URL(string: "http://maps.apple.com/?q=\(query)") {
            // なければ標準のマップアプリを使用
            UIApplication.shared.open(appleMapsUrl)
        }
    }

    /// URLをブラウザで開く
    private func executeOpenURLAction(_ action: ProposedAction) {
        if let url = URL(string: action.value) {
            UIApplication.shared.open(url)
        }
    }

    /// 電話を発信する
    private func executeCallAction(_ action: ProposedAction) {
        // 電話番号から数字のみを抽出
        let filteredPhoneNumber = action.value.filter("0123456789".contains)
        if let url = URL(string: "tel://\(filteredPhoneNumber)") {
            UIApplication.shared.open(url)
        }
    }
}
