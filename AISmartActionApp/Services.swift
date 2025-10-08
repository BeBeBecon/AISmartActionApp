import Foundation
import EventKit
import EventKitUI
import Contacts
import ContactsUI
import UIKit

// MARK: - Calendar Service
// ----------------------------------
// EventKitフレームワークを使い、iOSの標準カレンダーと連携するクラス
// ----------------------------------
class CalendarService: NSObject, EKEventEditViewDelegate {
    
    private let eventStore = EKEventStore()
    var onDismiss: (() -> Void)?

    /// カレンダーへのアクセス許可をリクエストし、許可されればイベント追加UIを表示する
    func addEvent(title: String, date: Date?, endDate: Date?, notes: String?, from viewController: UIViewController) {
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        
        switch authStatus {
        case .authorized, .fullAccess, .writeOnly:
            presentEventEditViewController(title: title, date: date, endDate: endDate, notes: notes, from: viewController)
            
        case .notDetermined:
            eventStore.requestFullAccessToEvents { (granted, error) in
                DispatchQueue.main.async {
                    if granted {
                        self.presentEventEditViewController(title: title, date: date, endDate: endDate, notes: notes, from: viewController)
                    } else {
                        print("❌ [CalendarService] カレンダー権限が拒否されました")
                    }
                }
            }
            
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.showSettingsAlert(from: viewController)
            }
            
        @unknown default:
            print("❌ [CalendarService] 不明な権限状態")
        }
    }

    /// イベント作成用のUI（シート）を画面に表示する
    private func presentEventEditViewController(title: String, date: Date?, endDate: Date?, notes: String?, from viewController: UIViewController) {
        let eventEditVC = EKEventEditViewController()
        eventEditVC.eventStore = eventStore
        
        let newEvent = EKEvent(eventStore: eventStore)
        newEvent.title = title
        newEvent.notes = notes
        newEvent.calendar = eventStore.defaultCalendarForNewEvents
        
        if let startDate = date {
            newEvent.startDate = startDate
            // AIが終了時刻を提案していればそれを使い、なければ1時間後をデフォルトとする
            newEvent.endDate = endDate ?? startDate.addingTimeInterval(3600)
        } else {
            let now = Date()
            newEvent.startDate = now
            newEvent.endDate = now.addingTimeInterval(3600)
        }
        
        eventEditVC.event = newEvent
        eventEditVC.editViewDelegate = self
        
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
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        switch action {
        case .saved:    print("✅ [CalendarService] イベントが保存されました！")
        case .canceled: print("❌ [CalendarService] イベントの追加がキャンセルされました")
        case .deleted:  print("🗑️ [CalendarService] イベントが削除されました")
        @unknown default: print("⚠️ [CalendarService] 不明なアクション")
        }
        controller.dismiss(animated: true, completion: onDismiss)
    }
}


// MARK: - Contacts Service
// ----------------------------------
// ContactsUIフレームワークを使い、iOSの標準連絡先と連携するクラス
// ----------------------------------
class ContactsService: NSObject, CNContactViewControllerDelegate {
    
    var onDismiss: (() -> Void)?
    
    func addContact(name: String, phone: String?, email: String?, from viewController: UIViewController) {
        let newContact = CNMutableContact()
        let nameComponents = name.components(separatedBy: .whitespaces)
        newContact.givenName = nameComponents.first ?? ""
        if nameComponents.count > 1 {
            newContact.familyName = nameComponents.last ?? ""
        }
        
        if let phone = phone {
            newContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        if let email = email {
            newContact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        
        let contactVC = CNContactViewController(forNewContact: newContact)
        contactVC.delegate = self
        
        let navigationController = UINavigationController(rootViewController: contactVC)
        viewController.present(navigationController, animated: true)
    }
    
    // MARK: - CNContactViewControllerDelegate
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.dismiss(animated: true, completion: onDismiss)
    }
}

