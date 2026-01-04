import SwiftUI

struct ContentView: View {
    // MARK: - State
    @State private var responseText: String = "Tap a test to run"
    @State private var isLoading: Bool = false
    @State private var loadedImage: UIImage?
    
    // Categorized test cases
    private let testCategories: [String: [String]] = [
        "CRUD": ["GET Post", "POST Create", "PUT Update", "PATCH Partial", "DELETE"],
        "Image & JSON": ["GET Image", "GET Large JSON", "POST Large JSON", "Slow Request (Timeout Test)"],
        "Auth & Status": ["Auth Bearer", "Auth Fail (401)", "401 Unauthorized", "403 Forbidden", "404 Not Found", "500 Internal Server Error", "503 Service Unavailable"],
        "Upload": ["Multipart Upload"],
        "Other": ["Query Params", "Multiple Requests Test"] // <- added
    ]
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 44))
                            .foregroundStyle(.blue)
                        Text("API Tester")
                            .font(.title2.bold())
                    }
                    .padding()
                    
                    // Test list (Top half)
                    List {
                        ForEach(testCategories.keys.sorted(), id: \.self) { category in
                            Section(header: Text(category)) {
                                ForEach(testCategories[category]!, id: \.self) { test in
                                    Button(action: {
                                        Task { await runTest(named: test) }
                                    }) {
                                        Label(test, systemImage: iconForTest(test))
                                            .foregroundColor(.primary)
                                            .padding(.vertical, 6)
                                    }
                                    .disabled(isLoading)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .frame(height: geometry.size.height * 0.5)
                    
                    Divider()
                    
                    // Preview & Response (Bottom half)
                    ScrollView {
                        VStack(spacing: 16) {
                            // Image preview
                            if let image = loadedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .padding(.horizontal)
                            }
                            
                            // Response area
                            ResponseView(responseText: $responseText, isLoading: $isLoading)
                                .padding(.horizontal)
                                .padding(.bottom)
                        }
                    }
                    .frame(height: geometry.size.height * 0.5)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
    }
    
    // MARK: - Helpers
    private func iconForTest(_ test: String) -> String {
        switch test {
        case "GET Post", "GET Image", "GET Large JSON", "POST Large JSON", "Query Params": return "arrow.down.circle"
        case "POST Create", "Multipart Upload": return "arrow.up.circle"
        case "PUT Update", "PATCH Partial": return "square.and.pencil"
        case "DELETE": return "trash"
        case "Auth Bearer", "Auth Fail (401)": return "lock"
        case "Slow Request (Timeout Test)": return "hourglass"
        case "401 Unauthorized", "403 Forbidden": return "exclamationmark.shield"
        case "404 Not Found": return "questionmark"
        case "500 Internal Server Error", "503 Service Unavailable": return "xmark.octagon"
        case "Multiple Requests Test": return "arrow.triangle.2.circlepath"
        default: return "gear"
        }
    }
    
    // MARK: - Test Runner
    private func runTest(named testName: String) async {
        isLoading = true
        responseText = "Loading..."
        loadedImage = nil
        
        switch testName {
        case "GET Post": await getSinglePost()
        case "POST Create": await createPost()
        case "PUT Update": await updatePost(method: "PUT")
        case "PATCH Partial": await updatePost(method: "PATCH")
        case "DELETE": await deletePost()
        case "GET Image": await loadImage()
        case "GET Large JSON": await loadLargeJSON()
        case "POST Large JSON": await postLargeJSON()
        case "Slow Request (Timeout Test)": await slowRequest()
        case "Multipart Upload": await multipartUpload()
        case "Auth Bearer": await authenticatedRequest(valid: true)
        case "Auth Fail (401)": await authenticatedRequest(valid: false)
        case "Query Params": await requestWithQueryParams()
        case "401 Unauthorized": await testHTTPStatus(401)
        case "403 Forbidden": await testHTTPStatus(403)
        case "404 Not Found": await testHTTPStatus(404)
        case "500 Internal Server Error": await testHTTPStatus(500)
        case "503 Service Unavailable": await testHTTPStatus(503)
        case "Multiple Requests Test": await multipleRequestsTest() // <- new
        default: responseText = "Unknown test"
        }
        
        isLoading = false
    }
    
    // MARK: - HTTP Status Test Helper
    private func testHTTPStatus(_ statusCode: Int) async {
        guard let url = URL(string: "https://httpbin.org/status/\(statusCode)") else {
            responseText = "Invalid URL"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        await executeRequest(request)
    }
    
    // MARK: - Network Helpers
    private func performJSONRequest(urlString: String, method: String, body: [String: Any]? = nil, timeout: TimeInterval? = nil) async {
        guard let url = URL(string: urlString) else { responseText = "Invalid URL"; return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Swift-Tester/1.0", forHTTPHeaderField: "User-Agent")
        if let timeout = timeout { request.timeoutInterval = timeout }
        if let body = body {
            do { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
            catch { responseText = "JSON encoding error: \(error.localizedDescription)"; return }
        }
        await executeRequest(request)
    }
    
    private func executeRequest(_ request: URLRequest) async {
        // MARK: - Request Logging
        print("\n" + String(repeating: "=", count: 60))
        print("🚀 [REQUEST] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("📋 [HEADERS]")
            headers.forEach { print("   \($0.key): \($0.value)") }
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("📦 [BODY] \(bodyString)")
        }
        print(String(repeating: "-", count: 60))
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("❌ [ERROR] Invalid response")
                responseText = "Invalid response"
                return
            }
            
            let bodyText = String(data: data, encoding: .utf8) ?? "(binary data)"
            let truncated = bodyText.count > 2000 ? String(bodyText.prefix(2000)) + "\n... (truncated)" : bodyText
            
            // MARK: - Response Logging
            print("✅ [RESPONSE] Status: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))")
            print("📋 [RESPONSE HEADERS]")
            http.allHeaderFields.forEach { print("   \($0.key): \($0.value)") }
            print("📦 [RESPONSE BODY]")
            print(truncated) // Truncated body for console debugging
            print(String(repeating: "=", count: 60) + "\n")
            
            responseText = """
            \(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "")
            Status: \(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            
            Headers:
            \(http.allHeaderFields.map { "\($0): \($1)" }.joined(separator: "\n"))
            
            Body:
            \(truncated)
            """
        } catch let urlError as URLError {
            print("❌ [ERROR] \(urlError.code == .timedOut ? "Request timed out" : urlError.localizedDescription)")
            print(String(repeating: "=", count: 60) + "\n")
            responseText = urlError.code == .timedOut ? "Request timed out" : "Network error: \(urlError.localizedDescription)"
        } catch {
            print("❌ [ERROR] \(error.localizedDescription)")
            print(String(repeating: "=", count: 60) + "\n")
            responseText = "Request failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Individual Test Methods
    private func getSinglePost() async { await performJSONRequest(urlString: "https://jsonplaceholder.typicode.com/posts/1", method: "GET") }
    private func createPost() async { await performJSONRequest(urlString: "https://jsonplaceholder.typicode.com/posts", method: "POST", body: ["title":"New Post","body":"Hello","userId":1]) }
    private func updatePost(method: String) async { await performJSONRequest(urlString: "https://jsonplaceholder.typicode.com/posts/1", method: method, body: ["id":1,"title":"Updated","body":"Updated","userId":1]) }
    private func deletePost() async { await performJSONRequest(urlString: "https://jsonplaceholder.typicode.com/posts/1", method: "DELETE") }
    private func loadLargeJSON() async { await performJSONRequest(urlString: "https://raw.githubusercontent.com/miloyip/nativejson-benchmark/master/data/citm_catalog.json", method: "GET") }
    
    private func postLargeJSON() async {
        var body: [String: Any] = [:]
        for i in 1...100 {
            body["item_\(i)"] = "This is a large piece of data for item \(i) to test large JSON request and response payloads."
            body["nested_\(i)"] = ["id": i, "value": Double.random(in: 0...1000), "active": true]
        }
        await performJSONRequest(urlString: "https://httpbin.org/post", method: "POST", body: body)
    }
    
    private func loadImage() async {
        guard let url = URL(string: "https://picsum.photos/800/600") else { responseText = "Invalid image URL"; return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let image = UIImage(data: data) { await MainActor.run { loadedImage = image } }
            if let http = response as? HTTPURLResponse {
                responseText = "GET Image\nStatus: \(http.statusCode)\nSize: \(data.count) bytes"
            }
        } catch { responseText = "Image load failed: \(error.localizedDescription)" }
    }
    
    private func slowRequest() async { await performJSONRequest(urlString: "https://httpbin.org/delay/8", method: "GET", timeout: 5) }
    
    private func multipartUpload() async {
        guard let url = URL(string: "https://httpbin.org/post") else { responseText = "Invalid URL"; return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let placeholder = "Fake image data".data(using: .utf8)!
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\nMy Vacation Photo\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(placeholder)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        await executeRequest(request)
    }
    
    private func authenticatedRequest(valid: Bool) async {
        var request = URLRequest(url: URL(string: "https://httpbin.org/bearer")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(valid ? "valid-bearer" : "invalid")", forHTTPHeaderField: "Authorization")
        await executeRequest(request)
    }
    
    private func requestWithQueryParams() async {
        var components = URLComponents(string: "https://httpbin.org/get")!
        components.queryItems = [
            URLQueryItem(name: "search", value: "swift network"),
            URLQueryItem(name: "page", value: "1")
        ]
        await performJSONRequest(urlString: components.url!.absoluteString, method: "GET")
    }
    
    // MARK: - Multiple Requests Test
    private func multipleRequestsTest() async {
        responseText = "Starting multiple requests...\n"
        
        // Define 3 URLs with different delays
        let urls = [
            URL(string: "https://httpbin.org/delay/3")!, // slower request
            URL(string: "https://httpbin.org/delay/1")!, // faster request
            URL(string: "https://httpbin.org/delay/2")!  // medium
        ]
        
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        let body = String(data: data, encoding: .utf8) ?? "(binary data)"
                        let truncated = body.count > 500 ? String(body.prefix(500)) + "..." : body
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        return (index, "Request \(index+1) done. Status: \(status)\nBody:\n\(truncated)\n")
                    } catch {
                        return (index, "Request \(index+1) failed: \(error.localizedDescription)\n")
                    }
                }
            }
            
            // Collect results as they finish
            for await (_, resultText) in group {
                await MainActor.run {
                    responseText += "\n\(resultText)"
                }
            }
        }
        
        await MainActor.run {
            responseText += "\nAll requests finished."
        }
    }
}

// MARK: - Response View
fileprivate struct ResponseView: View {
    @Binding var responseText: String
    @Binding var isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Response").font(.headline)
                Spacer()
                if isLoading { ProgressView() }
            }
            ScrollView {
                Text(responseText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

#Preview {
    ContentView()
}
