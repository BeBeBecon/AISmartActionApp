import SwiftUI
import PhotosUI

// MARK: - ImagePicker (UIKit Wrapper)
// ----------------------------------
// SwiftUIには、写真ライブラリを直接表示する機能がまだ限定的です。
// そのため、古くからあるUIKitのUIImagePickerControllerという部品を
// SwiftUIで使えるように「ラップ」しています。
// このファイルは、そのための決まり文句のようなコードです。
// ----------------------------------

/// SwiftUIでUIImagePickerControllerを利用するためのラッパー構造体
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage? // ContentViewの@State変数と連携
    @Environment(\.presentationMode) private var presentationMode // モーダルを閉じるために使用

    // ViewController（画面）を生成する時に呼ばれる
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator // イベントの通知先としてCoordinatorを設定
        return picker
    }

    // ViewControllerが更新された時に呼ばれる（今回は何もしない）
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // SwiftUIとUIKitの間の調整役（Coordinator）を生成する
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // UIImagePickerControllerからのイベント（画像が選択された、キャンセルされた等）を受け取るクラス
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        // 画像が選択された時に呼ばれるデリゲートメソッド
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // 選択された画像を親（ImagePicker）経由でContentViewの@State変数に渡す
                parent.selectedImage = image
            }
            // モーダルを閉じる
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

