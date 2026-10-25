import SwiftUI
import UIKit
import LFGCore

@MainActor
final class ShareViewController: UIViewController {
    #if DEBUG
    private var heldCanvasConfirmation = false
    #endif
    private var hosting: UIHostingController<ShareComposerView>?
    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        heldCanvasConfirmation = false
        #endif
        preferredContentSize = CGSize(width: 540, height: 720)
        guard let spool = ShareEnvironment.spool else {
            let label = UILabel(); label.text = ShareCaptureError.unavailable.localizedDescription
            label.numberOfLines = 0; label.textAlignment = .center
            label.frame = view.bounds.insetBy(dx: 24, dy: 24); label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label); return
        }
        let model = ShareComposerModel(spool: spool)
        #if DEBUG
        let isCanvasFixture = ShareCanvasFixture.apply(to: model)
        #endif
        let root = ShareComposerView(model: model) { [weak self] in
            #if DEBUG
            if isCanvasFixture, let self, !self.heldCanvasConfirmation,
               model.delivery?.status == .sent || model.delivery?.status == .queued {
                self.heldCanvasConfirmation = true
                return
            }
            #endif
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: root)
        hosting = host; addChild(host); view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        #if DEBUG
        if isCanvasFixture { return }
        #endif
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task {
            do {
                let input = try await ShareInputLoader.load(items, spool: spool)
                model.inputID = input.id; model.text = input.text; model.previewTitle = input.previewTitle; model.files = input.files; model.loadingInput = false
            } catch { model.inputError = error.localizedDescription; model.loadingInput = false }
            await model.refresh()
        }
    }
}
