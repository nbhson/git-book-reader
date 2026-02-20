import SwiftUI
import MarkdownUI // 1. Thêm import thư viện

struct MarkdownReaderView: View {
    let file: FileNode
    
    @StateObject private var service = GitHubService()
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
        .task(id: file.id) {
            await loadContent()
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
