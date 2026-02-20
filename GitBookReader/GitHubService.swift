import Foundation
import Combine

class GitHubService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store the tree data as a nested structure
    @Published var rootNodes: [FileNode] = []
    
    // Feature 2: Lịch sử Repos gần đây
    @Published var recentRepos: [String] = [] {
        didSet {
            UserDefaults.standard.set(recentRepos, forKey: "recentRepos")
        }
    }
    
    // Feature 2: Bộ nhớ đệm giữ file markdown
    private let rawFileCache = NSCache<NSString, NSString>()
    
    init() {
        if let savedRepos = UserDefaults.standard.array(forKey: "recentRepos") as? [String] {
            self.recentRepos = savedRepos
        }
    }
    
    func loadRepository(urlString: String) {
        let cleanedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isLoading = true
        errorMessage = nil
        rootNodes = []
        
        guard let (owner, repo) = extractOwnerAndRepo(from: cleanedUrl) else {
            self.errorMessage = "Invalid GitHub URL. Example: https://github.com/apple/swift"
            self.isLoading = false
            return
        }
        
        // Lưu vào History nếu hợp lệ
        if !recentRepos.contains(cleanedUrl) {
            recentRepos.insert(cleanedUrl, at: 0)
            if recentRepos.count > 20 { recentRepos.removeLast() } // Lưu tối đa 20 cái
        }
        
        Task {
            do {
                let defaultBranch = try await fetchDefaultBranch(owner: owner, repo: repo)
                let treeItems = try await fetchTree(owner: owner, repo: repo, branch: defaultBranch)
                let nodes = buildTree(from: treeItems, owner: owner, repo: repo, branch: defaultBranch)
                
                await MainActor.run {
                    self.rootNodes = nodes
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Networking
    
    private func fetchDefaultBranch(owner: String, repo: String) async throws -> String {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(RepoResponse.self, from: data)
        return response.defaultBranch
    }
    
    private func fetchTree(owner: String, repo: String, branch: String) async throws -> [GitTreeItem] {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.setValue("GitBookReader-App", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 403 {
             throw NSError(domain: "RateLimit", code: 403, userInfo: [NSLocalizedDescriptionKey: "GitHub API rate limit exceeded. Try again later."])
        }
        
        do {
            let treeResponse = try JSONDecoder().decode(GitTreeResponse.self, from: data)
            return treeResponse.tree
        } catch {
            print("Failed to decode: \(String(data: data, encoding: .utf8) ?? "")")
            throw error
        }
    }
    
    func fetchRawContent(downloadUrl: URL) async throws -> String {
        let cacheKey = NSString(string: downloadUrl.absoluteString)
        
        // 1. Kiểm tra Cache trước
        if let cachedContent = rawFileCache.object(forKey: cacheKey) {
            return String(cachedContent)
        }
        
        // 2. Nếu không có ở Cache thì tải xuống (Download)
        let (data, _) = try await URLSession.shared.data(from: downloadUrl)
        if let content = String(data: data, encoding: .utf8) {
            // 3. Lưu vào Cache
            rawFileCache.setObject(NSString(string: content), forKey: cacheKey)
            return content
        } else {
            throw NSError(domain: "Decoding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode text file"])
        }
    }
    
    // MARK: - Helpers
    
    private func extractOwnerAndRepo(from url: String) -> (String, String)? {
        let cleanedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = cleanedUrl.components(separatedBy: "/")
        
        guard let gitIndex = components.firstIndex(of: "github.com"), gitIndex + 2 < components.count else {
            return nil
        }
        
        let owner = components[gitIndex + 1]
        let repo = components[gitIndex + 2].replacingOccurrences(of: ".git", with: "")
        return (owner, repo)
    }
    
    private func buildTree(from items: [GitTreeItem], owner: String, repo: String, branch: String) -> [FileNode] {
        var nodesMap: [String: FileNode] = [:]
        var rootLevel: [FileNode] = []
        
        for item in items {
            if item.type != "tree" && !item.path.lowercased().hasSuffix(".md") { continue }
            
            let isDir = (item.type == "tree")
            let components = item.path.components(separatedBy: "/")
            let name = components.last ?? item.path
            
            var downloadUrl: URL? = nil
            if !isDir {
                let encodedPath = components.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.joined(separator: "/")
                let urlString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(encodedPath)"
                downloadUrl = URL(string: urlString)
            }
            
            let node = FileNode(name: name, path: item.path, isDirectory: isDir, downloadUrl: downloadUrl, children: isDir ? [] : nil)
            nodesMap[item.path] = node
        }
        
        for (_, node) in nodesMap {
            let path = node.path
            let components = path.components(separatedBy: "/")
            
            if components.count == 1 {
                rootLevel.append(node)
            } else {
                var parentPath = components
                parentPath.removeLast()
                let parentKey = parentPath.joined(separator: "/")
                
                if let parentNode = nodesMap[parentKey] {
                    if parentNode.children == nil { parentNode.children = [] }
                    parentNode.children?.append(node)
                }
            }
        }
        
        var finalNodes = rootLevel
        sortNodes(nodes: &finalNodes)
        return pruneEmptyDirectories(nodes: finalNodes)
    }
    
    private func sortNodes(nodes: inout [FileNode]) {
        nodes.sort { a, b in
            if a.isDirectory && !b.isDirectory { return true }
            if !a.isDirectory && b.isDirectory { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
    
    private func pruneEmptyDirectories(nodes: [FileNode], parent: FileNode? = nil) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isDirectory {
                if let children = node.children, !children.isEmpty {
                    let prunedChildren = pruneEmptyDirectories(nodes: children, parent: nil) // Tạm thời nil để assign lại sau
                    if !prunedChildren.isEmpty {
                        let newNode = FileNode(name: node.name, path: node.path, isDirectory: true, downloadUrl: node.downloadUrl, children: prunedChildren, parent: parent)
                        for child in prunedChildren { child.parent = newNode }
                        // Sort lại cấp này
                        var sortedArray = result + [newNode]
                        sortNodes(nodes: &sortedArray)
                        result = sortedArray
                    }
                }
            } else {
                node.parent = parent
                result.append(node)
                sortNodes(nodes: &result)
            }
        }
        return result
    }
}
