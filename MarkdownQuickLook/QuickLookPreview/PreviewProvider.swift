import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            let rendered = try MarkdownRenderer.renderFile(at: request.fileURL)
            reply.stringEncoding = .utf8
            reply.title = rendered.title
            return Data(rendered.html.utf8)
        }
    }
}
