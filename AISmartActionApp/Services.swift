import Foundation
import EventKit      // iOSの標準カレンダーのデータにアクセスするためのフレームワーク
import EventKitUI    // カレンダーのUI（予定の追加画面など）を提供するためのフレームワーク
import Contacts      // iOSの標準連絡先のデータにアクセスするためのフレームワーク
import ContactsUI    // 連絡先のUI（連絡先の追加画面など）を提供するためのフレームワーク

// MARK: - Calendar Service
// ----------------------------------
// EventKitフレームワークを使い、iOSの標準カレンダーと連携するクラス
// ----------------------------------
class CalendarService: NSObject, EKEventEditViewDelegate {
    
    /// カレンダーのイベント情報を管理（読み書き）するためのオブジェクト
    private let eventStore = EKEventStore()
    
    /// イベント追加UIを閉じた後に、呼び出してほしい処理を格納するための変数
    var onDismiss: (() -> Void)?

    /// カレンダーへのアクセス許可をリクエストし、許可されればイベント追加UIを表示する
    /// - Parameters:
    ///   - title: 予定のタイトル
    ///   - date: 予定の日時
    ///   - viewController: このUIを表示する元の画面
    func addEvent(title: String, date: Date?, from viewController: UIViewController) {
        print("📅 [CalendarService] addEvent呼び出し - タイトル: \(title)")
        if let date = date {
            print("📅 [CalendarService] 日時: \(date)")
        } else {
            print("⚠️ [CalendarService] 警告: 日時がnil")
        }
        
        // 現在のカレンダーへのアクセス許可状態を確認
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        print("📅 [CalendarService] 権限状態: \(authStatus.rawValue)")
        
        switch authStatus {
        case .authorized, .fullAccess:
            // すでに許可されている場合
            print("✅ [CalendarService] カレンダー権限あり - イベント編集画面を表示")
            presentEventEditViewController(title: title, date: date, from: viewController)
            
        case .notDetermined:
            // まだ許可/不許可が選択されていない場合
            print("🔄 [CalendarService] カレンダー権限をリクエスト中...")
            // ユーザーに許可を求めるダイアログを表示する
            eventStore.requestFullAccessToEvents { (granted, error) in
                if let error = error {
                    print("❌ [CalendarService] 権限リクエストエラー: \(error.localizedDescription)")
                    return
                }
                
                // ユーザーが「許可」を選択した場合
                if granted {
                    print("✅ [CalendarService] カレンダー権限が許可されました")
                    // UIの更新はメインスレッドで行う必要があるため、DispatchQueue.main.asyncで囲む
                    DispatchQueue.main.async {
                        self.presentEventEditViewController(title: title, date: date, from: viewController)
                    }
                } else {
                    print("❌ [CalendarService] カレンダー権限が拒否されました")
                }
            }
            
        case .denied, .restricted:
            // アクセスが拒否されている、または制限されている場合
            print("❌ [CalendarService] カレンダーへのアクセスが拒否されています。")
            // 設定アプリへの誘導を提案
            DispatchQueue.main.async {
                self.showSettingsAlert(from: viewController)
            }
            
        case .writeOnly:
            print("⚠️ [CalendarService] 書き込み専用権限")
            presentEventEditViewController(title: title, date: date, from: viewController)
            
        @unknown default:
            print("❌ [CalendarService] 不明な権限状態")
        }
    }

    /// イベント作成用のUI（シート）を画面に表示する
    private func presentEventEditViewController(title: String, date: Date?, from viewController: UIViewController) {
        print("🎨 [CalendarService] イベント編集画面を構築中...")
        
        // iOS標準のイベント編集画面を作成
        let eventEditVC = EKEventEditViewController()
        eventEditVC.eventStore = eventStore
        
        // 新しいイベントオブジェクトを作成
        let newEvent = EKEvent(eventStore: eventStore)
        newEvent.title = title // AIが抽出したイベント名を設定
        
        // カレンダーを明示的に設定（デフォルトカレンダーを使用）
        newEvent.calendar = eventStore.defaultCalendarForNewEvents
        
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            print("📅 [CalendarService] デフォルトカレンダー: \(defaultCalendar.title)")
        } else {
            print("⚠️ [CalendarService] 警告: デフォルトカレンダーが見つかりません")
        }
        
        // もし日付がAIによって抽出されていたら、それを予定の開始日時に設定
        if let date = date {
            newEvent.startDate = date
            // 終了日時は、とりあえず開始時刻の1時間後に設定（ユーザーはUI上で自由に変更可能）
            newEvent.endDate = date.addingTimeInterval(3600)
            print("📅 [CalendarService] 開始: \(date), 終了: \(date.addingTimeInterval(3600))")
        } else {
            // 日付が設定されていない場合は、現在時刻から1時間後をデフォルトに設定
            let now = Date()
            newEvent.startDate = now
            newEvent.endDate = now.addingTimeInterval(3600)
            print("⚠️ [CalendarService] 日付未設定のため現在時刻を使用")
        }
        
        // 編集画面に新しいイベント情報をセット
        eventEditVC.event = newEvent
        // このクラス（CalendarService）が編集画面の操作（保存/キャンセル）を検知できるように設定
        eventEditVC.editViewDelegate = self
        
        // 画面に表示
        print("🎨 [CalendarService] イベント編集画面を表示します")
        viewController.present(eventEditVC, animated: true, completion: nil)
    }
    
    /// 設定アプリへの誘導アラートを表示
    private func showSettingsAlert(from viewController: UIViewController) {
        let alert = UIAlertController(
            title: "カレンダーへのアクセスが必要です",
            message: "カレンダーにイベントを追加するには、設定アプリでカレンダーへのアクセスを許可してください。",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "設定を開く", style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        
        viewController.present(alert, animated: true)
    }

    // MARK: - EKEventEditViewDelegate
    /// イベント編集画面でユーザーが「完了」または「キャンセル」を押したときに呼ばれるメソッド
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        print("📅 [CalendarService] イベント編集画面が閉じられました")
        
        switch action {
        case .saved:
            print("✅ [CalendarService] イベントが保存されました！")
            // イベントが保存されたことを確認
            if let event = controller.event {
                print("📅 保存されたイベント:")
                print("   - タイトル: \(event.title ?? "不明")")
                print("   - 開始: \(event.startDate)")
                print("   - 終了: \(event.endDate)")
                print("   - カレンダー: \(event.calendar?.title ?? "不明")")
                print("   - イベントID: \(event.eventIdentifier ?? "なし")")
            }
            
        case .canceled:
            print("❌ [CalendarService] イベントの追加がキャンセルされました")
            
        case .deleted:
            print("🗑️ [CalendarService] イベントが削除されました")
            
        @unknown default:
            print("⚠️ [CalendarService] 不明なアクション")
        }
        
        // 編集画面を閉じる
        controller.dismiss(animated: true, completion: onDismiss)
    }
}


// MARK: - Contacts Service
// ----------------------------------
// ContactsUIフレームワークを使い、iOSの標準連絡先と連携するクラス
// ----------------------------------
class ContactsService: NSObject, CNContactViewControllerDelegate {
    
    /// 連絡先追加UIを閉じた後に、呼び出してほしい処理を格納するための変数
    var onDismiss: (() -> Void)?
    
    /// 連絡先追加UIを表示する
    /// - Parameters:
    ///   - name: 氏名
    ///   - phone: 電話番号
    ///   - email: メールアドレス
    ///   - viewController: このUIを表示する元の画面
    func addContact(name: String, phone: String?, email: String?, from viewController: UIViewController) {
        // 新しい連絡先データを作成するための、編集可能なオブジェクト
        let newContact = CNMutableContact()
        
        // AIが抽出した氏名を姓と名に分割（単純なスペース区切り）
        let nameComponents = name.components(separatedBy: .whitespaces)
        newContact.givenName = nameComponents.first ?? "" // 名
        if nameComponents.count > 1 {
            newContact.familyName = nameComponents.last ?? "" // 姓
        }
        
        // 電話番号が抽出されていれば設定
        if let phone = phone {
            newContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        // メールアドレスが抽出されていれば設定
        if let email = email {
            newContact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        
        // 新規連絡先用のUIを作成
        let contactVC = CNContactViewController(forNewContact: newContact)
        // このクラスが連絡先画面の操作を検知できるように設定
        contactVC.delegate = self
        
        // 画面上部にナビゲーションバー（キャンセルボタンなど）を表示するためにUINavigationControllerでラップする
        let navigationController = UINavigationController(rootViewController: contactVC)
        // 画面に表示
        viewController.present(navigationController, animated: true)
    }
    
    // MARK: - CNContactViewControllerDelegate
    /// 連絡先画面が閉じたときに呼ばれるメソッド
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        // 連絡先画面を閉じる
        viewController.dismiss(animated: true, completion: onDismiss)
    }
}
