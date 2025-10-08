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
    func execute(_ action: ProposedAction, summary: String? = nil) {
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
        case .addNote:
            executeAddNoteAction(summary: summary)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let vc = self.rootViewController else { return }
            self.calendarService.addEvent(
                title: action.value,
                date: action.date,
                endDate: action.endDate,
                notes: action.tertiaryValue,
                from: vc
            )
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
        if let googleMapsUrl = URL(string: "comgooglemaps://?q=\(query)"), UIApplication.shared.canOpenURL(googleMapsUrl) {
            UIApplication.shared.open(googleMapsUrl)
        } else if let appleMapsUrl = URL(string: "http://maps.apple.com/?q=\(query)") {
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
        let filteredPhoneNumber = action.value.filter("0123456789".contains)
        if let url = URL(string: "tel://\(filteredPhoneNumber)") {
            UIApplication.shared.open(url)
        }
    }
    
    /// 【新規追加】メモアプリに要約内容を共有する
    private func executeAddNoteAction(summary: String?) {
        guard let summaryText = summary, !summaryText.isEmpty, let vc = rootViewController else { return }
        
        // OS標準の共有シートを作成
        let activityVC = UIActivityViewController(activityItems: [summaryText], applicationActivities: nil)
        
        // iPadでの表示崩れを防ぐための設定
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceView = vc.view
            popoverController.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        // 共有シートを表示
        vc.present(activityVC, animated: true, completion: nil)
    }
}

