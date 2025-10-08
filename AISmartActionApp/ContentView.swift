import SwiftUI
import VisionKit
import MapKit

// MARK: - Main Content View
// ----------------------------------
// アプリのメイン画面（UI）を担当。ロジックはViewModelに委任する。
// ----------------------------------
struct ContentView: View {
    
    // MARK: - State & ViewModel
    // ----------------------------------
    // @StateObjectでViewModelのインスタンスを生成・保持する
    // ----------------------------------
    @StateObject private var viewModel = YomitoriViewModel()
    
    // UIの表示状態を管理する（ViewModelには移動させない）
    @State private var selectedImage: UIImage?
    @State private var showPhotosPicker = false
    
    // アクション実行を専門に行うサービス
    private let actionExecutor = ActionExecutionService()

    /// アプリの処理ステップを定義する列挙型
    enum AnalysisStep {
        case initial          // 初期状態
        case summarizing      // 1. AIが要約・校正中
        case textSummarized   // 2. AIによる要約・校正が完了
        case actionsProposed  // 3. AIによるアクション提案が完了
    }

    // MARK: - Body
    // ----------------------------------
    // アプリの画面（UI）を組み立てる部分
    // ----------------------------------
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景のグラデーション
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.2)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 20) {
                        // アクション提案前は、画像選択エリアを表示
                        if viewModel.analysisStep != .actionsProposed {
                            imageSelectionArea
                                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                        }
                        // 現在の処理ステップに応じた結果表示エリア
                        resultDisplayArea
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("yomitori")
            .toolbar {
                // 初期状態以外のときに「やり直す」ボタンを表示
                if viewModel.analysisStep != .initial {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            viewModel.resetState()
                            selectedImage = nil // 画像もクリア
                        }) {
                            Label("やり直す", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showPhotosPicker) {
                ImagePicker(selectedImage: $selectedImage).ignoresSafeArea()
            }
            
            // チャット画面をシートとして表示（カレンダー登録専用）
            .sheet(isPresented: $viewModel.showChatSheet) {
                ChatView(viewModel: viewModel, onExecute: {
                    // チャット完了後、カレンダー登録を実行
                    if let finalAction = viewModel.finalizeChatAndPrepareAction() {
                        actionExecutor.execute(finalAction)
                    }
                })
            }
            
            .onChange(of: selectedImage) { _, newImage in
                if let newImage = newImage {
                    // 画像が選択されたら、ViewModelの処理を呼び出す
                    viewModel.recognizeTextAndSummarize(from: newImage)
                }
            }
        }
    }

    // MARK: - View Components (画面の部品)
    
    private var imageSelectionArea: some View {
        VStack(spacing: 15) {
            if let selectedImage {
                Image(uiImage: selectedImage).resizable().scaledToFit().frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20)).shadow(radius: 5)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).frame(height: 200)
                    Text("画像を選択してください").font(.headline).foregroundStyle(.secondary)
                }
            }
            Button { showPhotosPicker = true } label: {
                Label("ライブラリから選択", systemImage: "photo.on.rectangle.angled").fontWeight(.bold)
            }
            .buttonStyle(.bordered).tint(.accentColor)
        }
        .padding(.horizontal, 20)
    }
    
    /// 現在の処理ステップに応じて、表示するカードとボタンを切り替える
    private var resultDisplayArea: some View {
        VStack(spacing: 20) {
            // viewModelのanalysisStepプロパティを監視して、UIを切り替える
            switch viewModel.analysisStep {
            case .initial:
                EmptyView()
            
            case .summarizing:
                CardView(title: "AIが画像を解析中...", content: "テキストを抽出・校正しています。")

            case .textSummarized:
                CardView(title: "AIによる要約・校正", content: viewModel.summarizedText)

                ActionButton(
                    title: "アクションを提案",
                    systemImage: "wand.and.stars",
                    color: .purple,
                    isLoading: viewModel.isLoading
                ) {
                    viewModel.generateActionsFromSummary() // ViewModelのアクション生成メソッドを呼び出し
                }

            case .actionsProposed:
                if !viewModel.summarizedText.isEmpty {
                    CardView(title: "AIによる要約・校正", content: viewModel.summarizedText)
                }
                if !viewModel.proposedActions.isEmpty {
                    actionButtonsArea
                }
                else if !viewModel.llmRawOutput.isEmpty {
                    CardView(title: "提案されたアクション", content: viewModel.llmRawOutput)
                }
            }
        }
    }

    /// 提案されたアクションをボタンとして一覧表示する
    private var actionButtonsArea: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("提案されたアクション")
                .font(.title2)
                .bold()
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                ForEach(viewModel.proposedActions) { action in
                    actionButton(for: action)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    /// 個別のアクションボタンを生成する
    private func actionButton(for action: ProposedAction) -> some View {
        Button {
            // カレンダー登録の場合はチャットで対話的に調整
            if action.type == .addCalendarEvent {
                viewModel.startConversation(for: action)
            } else {
                // その他のアクションはActionExecutionService経由で実行
                actionExecutor.execute(action)
            }
        } label: {
            HStack(spacing: 15) {
                // アイコン
                Image(systemName: action.systemImageName)
                    .font(.title2)
                    .frame(width: 40, alignment: .center)
                    .foregroundColor(.accentColor)
                
                // テキスト情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.type.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(action.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    // カレンダー登録の場合は日時も表示
                    if action.type == .addCalendarEvent, let date = action.date {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // カレンダー登録の場合は「調整する」アイコン、それ以外は「実行」アイコン
                Image(systemName: action.type == .addCalendarEvent ? "bubble.left.and.bubble.right" : "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    
    // MARK: - Chat View
    // ----------------------------------
    // AIとの対話を行うためのチャット画面（カレンダー登録専用）
    // ----------------------------------
    struct ChatView: View {
        @ObservedObject var viewModel: YomitoriViewModel
        let onExecute: () -> Void // 実行ボタンが押されたときのコールバック
        
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // チャットメッセージ表示エリア
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(viewModel.conversation) { message in
                                    ChatMessageView(message: message)
                                        .id(message.id)
                                }
                                
                                // AI応答中のローディング表示
                                if viewModel.isLoading {
                                    HStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                        Text("AIが考え中...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.leading)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.conversation.count) { _, _ in
                            // 新しいメッセージが追加されたら自動スクロール
                            if let lastMessage = viewModel.conversation.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // メッセージ入力エリア
                    HStack(spacing: 12) {
                        TextField("メッセージを入力...", text: $viewModel.userMessage, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        
                        Button(action: {
                            viewModel.sendChatMessage()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundColor(viewModel.userMessage.isEmpty ? .gray : .accentColor)
                        }
                        .disabled(viewModel.userMessage.isEmpty || viewModel.isLoading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
                .navigationTitle("イベントの調整")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("カレンダーに登録") {
                            onExecute()
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.isLoading)
                    }
                }
            }
        }
    }

    /// チャットの吹き出しを表示するためのUI部品
    struct ChatMessageView: View {
        let message: ChatMessage
        
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                if message.role == .user {
                    Spacer(minLength: 60)
                }
                
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(message.role == .user ? Color.accentColor : Color(.systemGray5))
                        .foregroundColor(message.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                if message.role == .model {
                    Spacer(minLength: 60)
                }
            }
        }
    }
}


// MARK: - Reusable UI Components

/// 情報をカード形式で表示するための、再利用可能なUI部品
struct CardView: View {
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ScrollView { Text(content).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 100)
        }
        .padding().background(.ultraThinMaterial).cornerRadius(20).padding(.horizontal, 20)
    }
}

/// アプリ内で共通して使うアクションボタン
struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label(title, systemImage: systemImage)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .disabled(isLoading)
        .buttonStyle(.borderedProminent)
        .tint(color)
        .padding(.horizontal, 20)
    }
}
