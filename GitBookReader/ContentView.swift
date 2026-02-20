import SwiftUI

struct ContentView: View {
    @StateObject private var service = GitHubService()
    @State private var urlString: String = "https://github.com/apple/swift"
    @State private var searchText: String = ""
    @State private var showAllHistory: Bool = false
    
    // For iPad/Mac Split View Selection
    @State private var selectedFile: FileNode?
    
    @EnvironmentObject var settings: BookSettings
    
    // Derived property for filtering nodes
    var filteredNodes: [FileNode] {
        if searchText.isEmpty {
            return service.rootNodes
        } else {
            return filterTree(nodes: service.rootNodes, searchText: searchText)
        }
    }
    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar Menu
            VStack(spacing: 0) {
                // Header Area
                VStack(alignment: .leading, spacing: 12) {
                    
                    // History (Recent Repos)
                    if !service.recentRepos.isEmpty {
                        HStack {
                            Text("Mở Gần Đây:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if service.recentRepos.count > 5 {
                                Button("Xem tất cả (\(service.recentRepos.count))") {
                                    showAllHistory = true
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(service.recentRepos.prefix(5), id: \.self) { repoUrl in
                                    HStack(spacing: 6) {
                                        Button(action: {
                                            urlString = repoUrl
                                            selectedFile = nil
                                            service.loadRepository(urlString: repoUrl)
                                        }) {
                                            Text(URL(string: repoUrl)?.lastPathComponent ?? repoUrl)
                                                .font(.caption)
                                                .lineLimit(1)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.blue)
                                        
                                        Button(action: {
                                            withAnimation {
                                                service.recentRepos.removeAll { $0 == repoUrl }
                                            }
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    
                    TextField("Enter GitHub Repo URL", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit {
                            selectedFile = nil
                            service.loadRepository(urlString: urlString)
                        }
                    
                    Button(action: {
                        selectedFile = nil
                        service.loadRepository(urlString: urlString)
                    }) {
                        Text("Tải Repository")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Tree Content
                List(selection: $selectedFile) {
                    if service.isLoading {
                        ProgressView("Đang tải dữ liệu...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else if let error = service.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } else if filteredNodes.isEmpty && !service.rootNodes.isEmpty {
                        Text("Không tìm thấy kết quả phù hợp.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        // Gọi Custom View đệ quy để có thể tuỳ chỉnh toàn bộ Label
                        ForEach(filteredNodes) { node in
                            NodeRowView(node: node, selectedFile: $selectedFile)
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, prompt: "Tìm kiếm file...")
            }
            .navigationTitle("GitBook")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation {
                            settings.readingTheme = settings.readingTheme == .dark ? .light : .dark
                        }
                    } label: {
                        Image(systemName: settings.readingTheme == .dark ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(settings.readingTheme == .dark ? .blue : .orange)
                    }
                    .help("Chuyển đổi giao diện Sáng/Tối")
                }
            }
            
        } detail: {
            // MARK: - Detail Box
            VStack(spacing: 0) {
                // 1. Breadcrumbs
                BreadcrumbView(
                    selectedFile: $selectedFile,
                    rootName: urlString.components(separatedBy: "/").last ?? "Repo"
                )
                Divider()
                
                // 2. Nội dung chính
                if let file = selectedFile {
                    if file.isDirectory {
                        // Hiện Grid
                        FolderGridView(nodes: file.children ?? [], selectedFile: $selectedFile)
                    } else {
                        // Đọc Markdown
                        MarkdownReaderView(file: file)
                    }
                } else {
                    if service.rootNodes.isEmpty {
                        // Chưa load URL
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.magnifyingglass")
                                .font(.system(size: 80))
                                .foregroundColor(.blue.opacity(0.8))
                            Text("Nhập một Repository URL để bắt đầu.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Load thành công, đang ở Home
                        FolderGridView(nodes: service.rootNodes, selectedFile: $selectedFile)
                    }
                }
            }
            .navigationTitle(selectedFile?.name ?? "Trang chủ")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $showAllHistory) {
            RecentHistorySheet(
                service: service,
                urlString: $urlString,
                selectedFile: $selectedFile,
                isPresented: $showAllHistory
            )
        }
    }
    
    // MARK: - Search Logic
    // Đệ quy để lọc các file/thư mục chứa từ khóa
    private func filterTree(nodes: [FileNode], searchText: String) -> [FileNode] {
        var result: [FileNode] = []
        let searchLower = searchText.lowercased()
        
        for node in nodes {
            if node.isDirectory {
                if let children = node.children {
                    let filteredChildren = filterTree(nodes: children, searchText: searchText)
                    // Giữ lại folder nếu tên của nó match chữ, hoặc có file con bên trong match chữ
                    if node.name.lowercased().contains(searchLower) || !filteredChildren.isEmpty {
                        let newNode = FileNode(name: node.name, path: node.path, isDirectory: true, downloadUrl: node.downloadUrl, children: filteredChildren)
                        result.append(newNode)
                    }
                }
            } else {
                if node.name.lowercased().contains(searchLower) {
                    result.append(node)
                }
            }
        }
        return result
    }
}

// MARK: - Custom Recursive Row View 
struct NodeRowView: View {
    let node: FileNode
    @Binding var selectedFile: FileNode?
    @State private var isExpanded: Bool = false
    
    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        NodeRowView(node: child, selectedFile: $selectedFile)
                    }
                }
            } label: {
                // Nút bấm này sẽ "nuốt" Tap, giúp click vào chữ chỉ để select (mở grid bên phải)
                // Cố ý không cho nó toggle isExpanded
                Button(action: {
                    selectedFile = node
                }) {
                    HStack {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .foregroundColor(.blue)
                        Text(node.name)
                            .fontWeight(selectedFile == node ? .bold : .semibold)
                            .foregroundColor(selectedFile == node ? .blue : .primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        } else {
            // Hiển thị file .md
            NavigationLink(value: node) {
                HStack {
                    Image(systemName: "doc.plaintext.fill")
                        .foregroundColor(.gray)
                    Text(node.name.replacingOccurrences(of: ".md", with: ""))
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Breadcrumb View (Path Thanh ngang trên cùng)
struct BreadcrumbView: View {
    @Binding var selectedFile: FileNode?
    let rootName: String
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    Button(action: { selectedFile = nil }) {
                        HStack {
                            Image(systemName: "house.fill")
                            Text(rootName)
                        }
                        .foregroundColor(selectedFile == nil ? .primary : .blue)
                        .fontWeight(selectedFile == nil ? .bold : .regular)
                    }
                    .buttonStyle(.plain)
                    .id("root")
                    
                    if let file = selectedFile {
                        let path = file.breadcrumbPath
                        ForEach(path) { crumb in
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            Button(action: { selectedFile = crumb }) {
                                Text(crumb.name)
                                    .foregroundColor(crumb == file ? .primary : .blue)
                                    .fontWeight(crumb == file ? .bold : .regular)
                            }
                            .buttonStyle(.plain)
                            .id(crumb.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onChange(of: selectedFile) { _ in
                    // Scroll tới phần tử cuối cùng tự động nếu tràn màn hình
                    withAnimation {
                        proxy.scrollTo(selectedFile?.id ?? UUID(), anchor: .trailing)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Folder Grid View (Lưới Icon thư mục bự)
struct FolderGridView: View {
    let nodes: [FileNode]
    @Binding var selectedFile: FileNode?
    
    // Cấu hình linh hoạt cột theo kích thước màn hình
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                let sortedNodes = nodes.sorted { (a, b) in
                    if a.isDirectory && !b.isDirectory { return true }
                    if !a.isDirectory && b.isDirectory { return false }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                
                ForEach(sortedNodes) { child in
                    Button(action: {
                        selectedFile = child
                    }) {
                        VStack(spacing: 12) {
                            Image(systemName: child.isDirectory ? "folder.fill" : "doc.text.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 54, height: 54)
                                // Thư mục thì viền cam (orange style), file thì màu text
                                .foregroundColor(child.isDirectory ? .orange : .gray)
                                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                            
                            Text(child.name.replacingOccurrences(of: ".md", with: ""))
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

#Preview {
    ContentView()
        .environmentObject(BookSettings())
}

// MARK: - Recent History Sheet
struct RecentHistorySheet: View {
    @ObservedObject var service: GitHubService
    @Binding var urlString: String
    @Binding var selectedFile: FileNode?
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    
    var filteredRepos: [String] {
        if searchText.isEmpty {
            return service.recentRepos
        } else {
            return service.recentRepos.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRepos, id: \.self) { repo in
                    Button(action: {
                        urlString = repo
                        selectedFile = nil
                        service.loadRepository(urlString: repo)
                        isPresented = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(string: repo)?.lastPathComponent ?? repo)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(repo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let reposToDelete = indexSet.map { filteredRepos[$0] }
                    withAnimation {
                        service.recentRepos.removeAll { reposToDelete.contains($0) }
                    }
                }
            }
            .navigationTitle("Lịch sử Repository")
            .searchable(text: $searchText, prompt: "Tìm URL repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { isPresented = false }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if !service.recentRepos.isEmpty {
                        Button("Xóa tất cả", role: .destructive) {
                            withAnimation {
                                service.recentRepos.removeAll()
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
}

// Helper to bridge NSColor to UIColor macro-like for multiplatform
#if os(iOS)
typealias NSColor = UIColor
extension UIColor {
    static var windowBackgroundColor: UIColor { .systemGroupedBackground }
    static var textBackgroundColor: UIColor { .systemBackground }
}
#endif
