import AppKit
import WebKit

/// App-owned controls run in an isolated world; document scripts remain disabled.
@MainActor
final class PreviewCodeCopy: NSObject {
    private static let handlerName = "textUICopyCode"
    static let maximumCopyBytes = 10 * 1024 * 1024
    private let contentController: WKUserContentController
    private let relay = MessageRelay()

    init(configuration: WKWebViewConfiguration) {
        contentController = configuration.userContentController
        super.init()
        relay.owner = self
        contentController.addScriptMessageHandler(relay, contentWorld: .defaultClient, name: Self.handlerName)
        contentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd,
                                                    forMainFrameOnly: true, in: .defaultClient))
    }

    static func copy(_ body: Any, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let text = body as? String, text.utf8.count <= maximumCopyBytes else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private final class MessageRelay: NSObject, WKScriptMessageHandlerWithReply {
        weak var owner: PreviewCodeCopy?

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard owner != nil, message.frameInfo.isMainFrame,
                  message.name == PreviewCodeCopy.handlerName else {
                replyHandler(false, nil)
                return
            }
            replyHandler(PreviewCodeCopy.copy(message.body), nil)
        }
    }

    // No document text is interpolated into executable source. Capture text before
    // inserting controls so labels never become part of a copied code snippet.
    static let script = #"""
    (() => {
        const snippets = Array.from(document.querySelectorAll('pre, code'))
            .filter(node => node.tagName === 'PRE' || !node.parentElement.closest('pre, code'))
            .map(node => ({ node, text: node.textContent }));
        for (const { node, text } of snippets) {
            if (!node.parentNode) continue;
            const host = document.createElement('span');
            host.setAttribute('data-textui-copy-control', '');
            const block = node.tagName === 'PRE';
            host.style.display = block ? 'block' : 'inline-block';
            host.style.margin = block ? '0.5em 0 -0.4em' : '0 0.3em';
            const shadow = host.attachShadow({ mode: 'closed' });
            const style = document.createElement('style');
            style.textContent = `
                :host { color-scheme: light dark; }
                button { font: 11px -apple-system, sans-serif; cursor: pointer;
                    border: 1px solid color-mix(in srgb, CanvasText 25%, transparent);
                    border-radius: 5px; padding: 3px 7px;
                    background: Canvas; color: CanvasText; }
                button:hover { background: color-mix(in srgb, CanvasText 10%, Canvas); }
                button:focus-visible { outline: 2px solid Highlight; outline-offset: 2px; }
            `;
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = 'Kopieren';
            button.setAttribute('aria-label', block ? 'Codeblock kopieren' : 'Code kopieren');
            button.title = 'Code unverändert in die Zwischenablage kopieren';
            let reset;
            button.addEventListener('click', async event => {
                if (!event.isTrusted) return;
                event.preventDefault();
                event.stopPropagation();
                try {
                    const copied = await window.webkit.messageHandlers.textUICopyCode.postMessage(text);
                    button.textContent = copied ? 'Kopiert' : 'Nicht kopiert';
                } catch (_) {
                    button.textContent = 'Nicht kopiert';
                }
                clearTimeout(reset);
                reset = setTimeout(() => { button.textContent = 'Kopieren'; }, 1600);
            });
            shadow.append(style, button);
            node.parentNode.insertBefore(host, block ? node : node.nextSibling);
        }
    })();
    """#
}
