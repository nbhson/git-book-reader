import SwiftUI
import MarkdownUI // 1. Thêm import thư viện
import AVFoundation // Thêm AVFoundation cho Text-to-Speech
import Combine

// Trình quản lý Đọc văn bản
class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    
    private var pendingUtterancesCount = 0
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func toggleSpeech(text: String) {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            pendingUtterancesCount = 0
        } else {
            // Lọc các ký hiệu Markdown dể đọc tự nhiên hơn
            var cleanText = text
            
            do {
                // Xoá Code blocks (```...```)
                let codeBlockRegex = try NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
                cleanText = codeBlockRegex.stringByReplacingMatches(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText), withTemplate: "")
                
                // Xoá hình ảnh ![alt](url)
                let imageRegex = try NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\([^)]+\\)", options: [])
                cleanText = imageRegex.stringByReplacingMatches(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText), withTemplate: "")
                
                // Giữ lại text của Link, xoá URL: [text](url) -> text
                let linkRegex = try NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)", options: [])
                cleanText = linkRegex.stringByReplacingMatches(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText), withTemplate: "$1")
                
                // Xoá HTML tags
                let htmlRegex = try NSRegularExpression(pattern: "<[^>]+>", options: [])
                cleanText = htmlRegex.stringByReplacingMatches(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText), withTemplate: "")
            } catch {
                print("Regex Error: \(error)")
            }
            
            // Xoá các ký tự Markdown sót lại
            cleanText = cleanText
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: ">", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "-", with: "")
            
            // Tách thành các đoạn văn để đọc không bị gắt hoặc lỗi do chuỗi quá dài
            let paragraphs = cleanText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            guard !paragraphs.isEmpty else { return }
            
            pendingUtterancesCount = paragraphs.count
            
            for paragraph in paragraphs {
                let utterance = AVSpeechUtterance(string: paragraph)
                // Tự động chọn giọng đọc ưu tiên Tiếng Việt, nếu không có lấy mặc định
                if let voice = AVSpeechSynthesisVoice(language: "vi-VN") ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
                    utterance.voice = voice
                }
                utterance.rate = 0.5 // Tốc độ vừa phải
                utterance.preUtteranceDelay = 0.1 // Nghỉ 0.1s giữa các đoạn văn
                
                synthesizer.speak(utterance)
            }
            
            isSpeaking = true
        }
    }
    
    func stop() {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            pendingUtterancesCount = 0
        }
    }
    
    // Delegate callbacks
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingUtterancesCount -= 1
        if pendingUtterancesCount <= 0 {
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.pendingUtterancesCount = 0
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.pendingUtterancesCount = 0
        }
    }
}

struct MarkdownReaderView: View {
    let file: FileNode
    
    @StateObject private var service = GitHubService()
    @StateObject private var speechManager = SpeechManager()
    @State private var markdownText: String = ""
    
    // Khai báo Settings
    @EnvironmentObject var settings: BookSettings
    
    var body: some View {
        ZStack {
            // Background của giao diện đọc sách
            settings.backgroundColor.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if service.isLoading {
                        ProgressView("Loading content...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 50)
                    } else if let error = service.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else if !markdownText.isEmpty {
                        // 2. Sử dụng MarkdownUI
                        Markdown(markdownText)
                            .markdownTheme(.gitHub)
                            .padding()
                            .textSelection(.enabled)
                            // Áp dụng scale kích thước Font chư
                            .scaleEffect(settings.fontSizeMultiplier, anchor: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(file.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    // Nút Đọc văn bản (Text-to-Speech)
                    Button {
                        speechManager.toggleSpeech(text: markdownText)
                    } label: {
                        Image(systemName: speechManager.isSpeaking ? "speaker.wave.3.fill" : "speaker.slash.fill")
                            .foregroundColor(speechManager.isSpeaking ? .blue : .primary)
                    }
                    .disabled(markdownText.isEmpty)
                    .help("Đọc văn bản")
                    
                    // Nút cài đặt (Font, Theme)
                    Menu {
                        Section("Cỡ chữ (Font Size)") {
                            Button("Phóng to (A+)") { settings.fontSizeMultiplier = min(settings.fontSizeMultiplier + 0.2, 2.0) }
                            Button("Thu nhỏ (A-)") { settings.fontSizeMultiplier = max(settings.fontSizeMultiplier - 0.2, 0.6) }
                            Button("Mặc định") { settings.fontSizeMultiplier = 1.0 }
                        }
                        
                        Section("Màu nền (Theme)") {
                            ForEach(BookSettings.Theme.allCases) { theme in
                                Button {
                                    settings.readingTheme = theme
                                } label: {
                                    HStack {
                                        Text(theme.displayName)
                                        if settings.readingTheme == theme {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                }
            }
        }
        .task(id: file.id) {
            await loadContent()
        }
        .onDisappear {
            speechManager.stop()
        }
    }
    
    private func loadContent() async {
        guard let url = file.downloadUrl else { return }
        service.isLoading = true
        service.errorMessage = nil
        do {
            let content = try await service.fetchRawContent(downloadUrl: url)
            
            // Xử lý chuỗi thô: thay thế "\n" literal bằng newline thực sự để Markdown parse đúng
            // Xử lý thêm các trường hợp xuống dòng của Windows (\r\n) hoặc lỗi khoảng trắng khi encode
            var processedContent = content
                .replacingOccurrences(of: "\\r\\n", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
            
            // Đảm bảo Heading (#) và Blockquote (>) luôn đứng ở đầu dòng mới (cách ra 1 dòng trống)
            // vì đôi khi MarkdownUI không parse block elements nếu nội dung trước nó dính vào nhau.
            do {
                // Thêm dòng trống trước các Heading (từ 1 đến 6 dấu #) nếu nó đang bị dính với chữ ở dòng trước
                let headingRegex = try NSRegularExpression(pattern: "([^\n])\n(#{1,6}\\s)", options: [])
                processedContent = headingRegex.stringByReplacingMatches(
                    in: processedContent,
                    range: NSRange(processedContent.startIndex..., in: processedContent),
                    withTemplate: "$1\n\n$2"
                )
                
                // Thêm dòng trống trước Blockquote (>)
                let quoteRegex = try NSRegularExpression(pattern: "([^\n])\n(>\\s)", options: [])
                processedContent = quoteRegex.stringByReplacingMatches(
                    in: processedContent,
                    range: NSRange(processedContent.startIndex..., in: processedContent),
                    withTemplate: "$1\n\n$2"
                )
                
            } catch {
                print("Regex parsing error: \(error)")
            }
            
            await MainActor.run {
                self.markdownText = processedContent
                self.service.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.service.errorMessage = "Failed to load: \(error.localizedDescription)"
                self.service.isLoading = false
            }
        }
    }
}
