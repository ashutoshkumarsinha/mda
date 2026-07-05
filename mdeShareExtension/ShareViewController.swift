import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processShare()
    }

    private func processShare() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            finish()
            return
        }

        let providers = item.attachments ?? []
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }) else {
            finish()
            return
        }

        let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : UTType.text.identifier

        provider.loadItem(forTypeIdentifier: type) { [weak self] value, _ in
            if let text = value as? String {
                SharePayloadStore.savePendingShare(text)
            } else if let url = value as? URL,
                      let text = try? String(contentsOf: url, encoding: .utf8) {
                SharePayloadStore.savePendingShare(text)
            }
            DispatchQueue.main.async {
                self?.finish()
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

enum SharePayloadStore {
    static let appGroupID = "group.name.aks.mde"
    private static let pendingShareKey = "mde.pendingShareText"

    static func savePendingShare(_ text: String) {
        UserDefaults(suiteName: appGroupID)?.set(text, forKey: pendingShareKey)
    }
}
