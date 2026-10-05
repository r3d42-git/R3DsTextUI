import Foundation
import Markdown

/// Produces an offline preview document. The hosting web view applies its resource
/// policy; raw HTML in Markdown is intentionally retained for authoring previews.
public enum MarkdownPreview {
    public static func html(from source: String) -> String {
        var renderer = Renderer()
        renderer.visit(Document(parsing: source))
        return document(body: renderer.output)
    }

    static func document(body: String) -> String {
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        :root { color-scheme: light dark; --background:#ffffff; --foreground:#263448; --muted:#65758b; --line:#dbe2eb; --code:#f1f4f8; --accent:#1767ab; }
        @media(prefers-color-scheme:dark) { :root { --background:#273449; --foreground:#d2dbea; --muted:#a0aec0; --line:#4a5c73; --code:#222e40; --accent:#70c7f1; } }
        * { box-sizing:border-box; }
        body { margin:0; background:var(--background); color:var(--foreground); font:16px/1.65 -apple-system,BlinkMacSystemFont,sans-serif; overflow-wrap:anywhere; }
        main { max-width:900px; margin:auto; padding:28px clamp(18px,5vw,48px) 64px; }
        h1,h2,h3,h4,h5,h6 { line-height:1.3; margin:1.5em 0 .6em; }
        h1 { font-size:2em; } h2 { font-size:1.5em; border-bottom:1px solid var(--line); padding-bottom:.3em; }
        main>:first-child { margin-top:0; } p,ul,ol,pre,blockquote,table { margin:0 0 1em; }
        li>p { margin:.25em 0; } li>ul,li>ol { margin-bottom:.25em; }
        a { color:var(--accent); } code { background:var(--code); border-radius:4px; padding:.15em .3em; font: .88em/1.55 Menlo,monospace; }
        pre { padding:16px; background:var(--code); border:1px solid var(--line); border-radius:8px; overflow:auto; overflow-wrap:normal; }
        pre code { padding:0; background:none; } blockquote { border-left:3px solid var(--accent); padding:.2em 1em; color:var(--muted); }
        blockquote>:last-child { margin-bottom:0; } .table-scroll { overflow-x:auto; margin-bottom:1em; } table { width:100%; border-collapse:collapse; margin:0; }
        th,td { border:1px solid var(--line); padding:8px 12px; text-align:left; } th { background:var(--code); }
        td[align=right],th[align=right] { text-align:right; } td[align=center],th[align=center] { text-align:center; }
        hr { border:0; border-top:1px solid var(--line); margin:1.5em 0; } img { max-width:100%; height:auto; }
        input[type=checkbox] { margin-right:.5em; accent-color:var(--accent); }
        .task-list-item { list-style:none; } .task-list-item>p:first-of-type { display:inline; }
        </style></head><body><main>\(body)</main></body></html>
        """
    }
}

private struct Renderer: MarkupWalker {
    var output = ""
    private var header = false
    private var alignments: [Table.ColumnAlignment?] = []
    private var column = 0

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private mutating func element(_ name: String, _ node: Markup, attributes: String = "") {
        output += "<\(name)\(attributes)>"
        descendInto(node)
        output += "</\(name)>"
    }

    mutating func visitHeading(_ heading: Heading) { element("h\(heading.level)", heading) }
    mutating func visitParagraph(_ paragraph: Paragraph) { element("p", paragraph) }
    mutating func visitStrong(_ strong: Strong) { element("strong", strong) }
    mutating func visitEmphasis(_ emphasis: Emphasis) { element("em", emphasis) }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { element("del", strikethrough) }
    mutating func visitBlockQuote(_ quote: BlockQuote) { element("blockquote", quote) }
    mutating func visitUnorderedList(_ list: UnorderedList) { element("ul", list) }
    mutating func visitOrderedList(_ list: OrderedList) { element("ol", list, attributes: " start=\"\(list.startIndex)\"") }
    mutating func visitListItem(_ item: ListItem) {
        output += item.checkbox == nil ? "<li>" : "<li class=\"task-list-item\">"
        if let checkbox = item.checkbox {
            output += "<input type=\"checkbox\" disabled\(checkbox == .checked ? " checked" : "")>"
        }
        descendInto(item)
        output += "</li>"
    }
    mutating func visitText(_ text: Text) { output += escape(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { output += "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { output += "<br>" }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) { output += "<hr>" }
    mutating func visitInlineCode(_ code: InlineCode) { output += "<code>\(escape(code.code))</code>" }
    mutating func visitCodeBlock(_ code: CodeBlock) {
        let language = code.language.map { " class=\"language-\(escape($0))\"" } ?? ""
        output += "<pre><code\(language)>\(escape(code.code))</code></pre>"
    }
    mutating func visitLink(_ link: Link) {
        var attributes = link.destination.map { " href=\"\(escape($0))\"" } ?? ""
        if let title = link.title { attributes += " title=\"\(escape(title))\"" }
        element("a", link, attributes: attributes)
    }
    mutating func visitImage(_ image: Image) {
        let source = image.source.map { " src=\"\(escape($0))\"" } ?? ""
        let title = image.title.map { " title=\"\(escape($0))\"" } ?? ""
        output += "<img\(source)\(title) alt=\"\(escape(image.plainText))\">"
    }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { output += html.rawHTML }
    mutating func visitInlineHTML(_ html: InlineHTML) { output += html.rawHTML }
    mutating func visitTable(_ table: Table) {
        alignments = table.columnAlignments
        output += "<div class=\"table-scroll\">"
        element("table", table)
        output += "</div>"
        alignments = []
    }
    mutating func visitTableHead(_ head: Table.Head) {
        header = true
        column = 0
        output += "<thead>"
        element("tr", head)
        output += "</thead>"
        header = false
    }
    mutating func visitTableBody(_ body: Table.Body) { element("tbody", body) }
    mutating func visitTableRow(_ row: Table.Row) { column = 0; element("tr", row) }
    mutating func visitTableCell(_ cell: Table.Cell) {
        let alignment = column < alignments.count ? alignments[column].map { " align=\"\($0)\"" } ?? "" : ""
        column += 1
        element(header ? "th" : "td", cell, attributes: alignment)
    }
}
