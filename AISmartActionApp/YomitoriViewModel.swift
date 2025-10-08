import SwiftUI
import Combine
import FoundationModels
import Vision

// MARK: - Yomitori ViewModel
// ----------------------------------
// UIの状態とロジックを管理する、アプリの「頭脳」
// ----------------------------------
@MainActor
class YomitoriViewModel: ObservableObject {
    
    // MARK: - Published Properties
    // ----------------------------------
    @Published var summarizedText = ""
    @Published var llmRawOutput = ""
    @Published var proposedActions: [ProposedAction] = []
    @Published var isLoading = false
    @Published var analysisStep: ContentView.AnalysisStep = .initial
    
    // MARK: - Services
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
    }
    
    /// 【ステップ1】 画像からテキストを認識し、AI要約を呼び出す
    func recognizeTextAndSummarize(from uiImage: UIImage) {
        analysisStep = .summarizing
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = uiImage.cgImage else {
                Task { await self.updateSummaryText("画像の変換に失敗しました。") }; return
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    Task { await self.updateSummaryText("エラー: \(error.localizedDescription)") }; return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    Task { await self.updateSummaryText("テキストが見つかりませんでした。") }; return
                }
                
                let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                print("🔍 [Vision] 認識されたテキスト: \(recognizedText)")
                
                Task {
                    await self.summarizeRecognizedText(recognizedText)
                }
            }
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            
            do { try requestHandler.perform([request]) }
            catch { Task { await self.updateSummaryText("テキスト認識の実行に失敗しました。") } }
        }
    }
    
    /// 【ステップ2】 抽出されたテキストを、AIに要約・校正させる
    private func summarizeRecognizedText(_ text: String) async {
        do {
            let summary = try await llmService.summarizeText(text)
            self.summarizedText = summary
            self.analysisStep = .textSummarized
            print("✅ [AI] 要約完了: \(summary)")
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
                var (rawOutput, parsedActions) = try await llmService.generateActions(from: summarizedText)
                
                // 「メモに追加」アクションがAIによって提案されなかった場合、手動で追加する
                let hasAddNoteAction = parsedActions.contains { $0.type == .addNote }
                if !hasAddNoteAction && !summarizedText.isEmpty {
                    // 要約文の最初の行をタイトルとして使用する
                    let noteTitle = summarizedText.split(separator: "\n").first.map(String.init) ?? "要約メモ"
                    let noteAction = ProposedAction(type: .addNote, value: noteTitle)
                    parsedActions.append(noteAction)
                }
                
                self.llmRawOutput = rawOutput
                self.proposedActions = parsedActions
                self.analysisStep = .actionsProposed
                print("🤖 [AI] 生成されたアクション:\n\(llmRawOutput)")
                print("✅ [Parser] パースされたアクション数: \(proposedActions.count)")
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
}
