import SwiftUI
import Combine
import FoundationModels
import Vision

// MARK: - Yomitori ViewModel
// ----------------------------------
// UIの状態とロジックを管理する、アプリの「頭脳」
// ObservableObjectに準拠し、UIに変更を通知できるようにする
// ----------------------------------
@MainActor // UIの更新を安全に行うため
class YomitoriViewModel: ObservableObject {
    
    // MARK: - Published Properties
    // ----------------------------------
    // @Publishedを付けることで、これらの変数の値が変わるとUIが自動的に再描画される
    // ----------------------------------
    @Published var summarizedText = "" // AIが校正・要約したテキスト
    @Published var llmRawOutput = ""
    @Published var proposedActions: [ProposedAction] = []
    @Published var isLoading = false
    
    // アプリの現在の処理ステップを管理するための状態変数
    @Published var analysisStep: ContentView.AnalysisStep = .initial
    
    // MARK: - Chat Properties
    // ----------------------------------
    // チャット機能のための状態管理（カレンダー登録専用）
    // ----------------------------------
    @Published var showChatSheet = false // チャット画面の表示/非表示
    @Published var conversation: [ChatMessage] = [] // チャットの会話履歴
    @Published var userMessage = "" // ユーザーの入力中メッセージ
    @Published var currentAction: ProposedAction? // 現在調整中のアクション
    
    // MARK: - Services
    // ----------------------------------
    // AIとの対話を担当するサービス
    // ----------------------------------
    private let llmService = LLMService()
    
    // MARK: - Logic (アプリの頭脳部分)

    /// UIの状態を初期状態に戻す
    func resetState() {
        summarizedText = ""
        llmRawOutput = ""
        proposedActions = []
        analysisStep = .initial
        isLoading = false
        
        // チャット関連の状態もリセット
        showChatSheet = false
        conversation = []
        userMessage = ""
        currentAction = nil
    }
    
    /// 【ステップ1】 画像からテキストを認識し、そのままAIによる要約処理を呼び出す
    func recognizeTextAndSummarize(from uiImage: UIImage) {
        analysisStep = .summarizing // 処理ステップを「要約中」に更新
        isLoading = true
        
        // テキスト認識は重い処理なのでバックグラウンドで実行
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = uiImage.cgImage else {
                Task { await self.updateSummaryText("画像の変換に失敗しました。") }; return
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            let request = VNRecognizeTextRequest { request, error in
                // Visionからのコールバック
                if let error = error {
                    Task { await self.updateSummaryText("エラー: \(error.localizedDescription)") }; return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    Task { await self.updateSummaryText("テキストが見つかりませんでした。") }; return
                }
                
                let topCandidates = observations.compactMap { $0.topCandidates(1).first?.string }
                let recognizedText = topCandidates.joined(separator: "\n")
                
                print("🔍 [Vision] 認識されたテキスト:")
                print(recognizedText)
                
                // テキスト認識が成功したら、すぐにAI要約タスクを実行
                Task {
                    await self.summarizeRecognizedText(recognizedText)
                }
            }
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate // 精度を最高に設定
            
            do { try requestHandler.perform([request]) }
            catch {
                Task { await self.updateSummaryText("テキスト認識の実行に失敗しました。") }
            }
        }
    }
    
    /// 【ステップ2】 抽出されたテキストを、AIに要約・校正させる
    private func summarizeRecognizedText(_ text: String) async {
        do {
            let summary = try await llmService.summarizeText(text)
            self.summarizedText = summary
            self.analysisStep = .textSummarized
            
            print("✅ [AI] 要約完了:")
            print(summary)
            
        } catch {
            await updateSummaryText("エラー：\(error.localizedDescription)")
        }
        self.isLoading = false
    }

    /// 【ステップ3】 要約されたテキストから、具体的なアクションを生成させる
    func generateActionsFromSummary() {
        Task {
            isLoading = true
            llmRawOutput = ""
            proposedActions = []
            
            do {
                let (rawOutput, parsedActions) = try await llmService.generateActions(from: summarizedText)
                
                self.llmRawOutput = rawOutput
                self.proposedActions = parsedActions
                self.analysisStep = .actionsProposed
                
                print("🤖 [AI] 生成されたアクション:")
                print(llmRawOutput)
                
                print("✅ [Parser] パースされたアクション数: \(proposedActions.count)")
                for (index, action) in proposedActions.enumerated() {
                    print("  \(index + 1). \(action.type.rawValue): \(action.value)")
                    if let date = action.date {
                        print("     日時: \(date)")
                    }
                }
                
            } catch {
                llmRawOutput = "エラー：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    /// エラーメッセージなどをUIに反映するためのヘルパー関数
    private func updateSummaryText(_ message: String) {
        self.summarizedText = message
        self.isLoading = false
    }
    
    // MARK: - Chat Logic
    // ----------------------------------
    // カレンダー登録アクションに対する対話的な調整機能
    // ----------------------------------
    
    /// カレンダー登録アクションに対して対話を開始する
    /// - Parameter action: 調整対象のカレンダーイベントアクション
    func startConversation(for action: ProposedAction) {
        guard action.type == .addCalendarEvent else { return }
        
        currentAction = action
        conversation = []
        
        // AIからの初回メッセージを生成（イベント内容の確認）
        let dateString: String
        if let date = action.date {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "ja_JP")
            dateString = formatter.string(from: date)
        } else {
            dateString = "日時未定"
        }
        
        let initialMessage = """
        以下の内容でカレンダーに登録します：
        
        📅 イベント名: \(action.value)
        🕐 日時: \(dateString)
        
        この内容で問題ありませんか？変更したい点があれば教えてください。
        （例: 「時刻を15時に変更して」「タイトルを〇〇に変えて」など）
        """
        
        conversation.append(ChatMessage(role: .model, content: initialMessage))
        showChatSheet = true
    }
    
    /// ユーザーからのチャットメッセージを送信し、AIからの応答を取得する
    func sendChatMessage() {
        guard !userMessage.isEmpty, let currentAction = currentAction else { return }
        
        let userInput = userMessage
        conversation.append(ChatMessage(role: .user, content: userInput))
        userMessage = ""
        
        Task {
            isLoading = true
            do {
                let (response, updatedAction) = try await llmService.adjustCalendarEvent(
                    action: currentAction,
                    conversationHistory: conversation,
                    userInput: userInput
                )
                
                conversation.append(ChatMessage(role: .model, content: response))
                self.currentAction = updatedAction
                
                // proposedActionsの中の該当アクションも更新（IDで検索）
                if let index = proposedActions.firstIndex(where: { $0.id == updatedAction.id }) {
                    proposedActions[index] = updatedAction
                }
                
            } catch {
                conversation.append(ChatMessage(role: .model, content: "エラーが発生しました: \(error.localizedDescription)"))
            }
            
            isLoading = false
        }
    }
    
    /// 対話が完了し、最終的なアクションを実行する準備ができたことを示す
    func finalizeChatAndPrepareAction() -> ProposedAction? {
        showChatSheet = false
        return currentAction
    }
}
