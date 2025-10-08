import SwiftUI
import VisionKit

// MARK: - Main Content View
// ----------------------------------
// アプリのメイン画面（UI）を担当。ロジックはViewModelに委任する。
// ----------------------------------
struct ContentView: View {
    
    // MARK: - State & ViewModel
    // ----------------------------------
    @StateObject private var viewModel = YomitoriViewModel()
    
    // UIの表示状態を管理する
    @State private var selectedImage: UIImage?
    @State private var showPhotosPicker = false
    
    // アクション実行を専門に行うサービス
    private let actionExecutor = ActionExecutionService()

    /// アプリの処理ステップを定義する列挙型
    enum AnalysisStep {
        case initial, summarizing, textSummarized, actionsProposed
    }

    // MARK: - Body
    // ----------------------------------
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.2)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.analysisStep != .actionsProposed {
                            imageSelectionArea
                                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                        }
                        resultDisplayArea
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("yomitori")
            .toolbar {
                if viewModel.analysisStep != .initial {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            viewModel.resetState()
                            selectedImage = nil
                        } label: {
                            Label("やり直す", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showPhotosPicker) {
                ImagePicker(selectedImage: $selectedImage).ignoresSafeArea()
            }
            .onChange(of: selectedImage) { _, newImage in
                if let newImage = newImage {
                    viewModel.recognizeTextAndSummarize(from: newImage)
                }
            }
        }
    }

    // MARK: - View Components
    
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
    
    private var resultDisplayArea: some View {
        VStack(spacing: 20) {
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
                    viewModel.generateActionsFromSummary()
                }
            case .actionsProposed:
                if !viewModel.summarizedText.isEmpty {
                    CardView(title: "AIによる要約・校正", content: viewModel.summarizedText)
                }
                if !viewModel.proposedActions.isEmpty {
                    actionButtonsArea
                } else if !viewModel.llmRawOutput.isEmpty {
                    CardView(title: "AIの解析結果", content: viewModel.llmRawOutput)
                }
            }
        }
    }

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
    
    private func actionButton(for action: ProposedAction) -> some View {
        Button {
            // --- 修正箇所 ---
            // 「メモに追加」アクションのために、要約テキストを渡す
            actionExecutor.execute(action, summary: viewModel.summarizedText)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: action.systemImageName)
                    .font(.title2)
                    .frame(width: 40, alignment: .center)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.type.rawValue).font(.headline).foregroundColor(.primary)
                    Text(action.value).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if action.type == .addCalendarEvent, let date = action.date {
                        HStack(spacing: 4) {
                            Image(systemName: "clock").font(.caption)
                            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        }.foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable UI Components
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

