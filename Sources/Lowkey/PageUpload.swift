import WebKit

enum PageUpload {
    /// macOS 10.15 has no `UniformTypeIdentifiers`; map the common extensions directly.
    static func attach(in view: WKWebView, startURL: URL, name: String, bytes: Data, field: String? = nil,
                       completion: @escaping (String) -> Void) {
        let ext = (name as NSString).pathExtension.lowercased()
        let mime = Self.mimeTypes[ext] ?? "application/octet-stream"
        let payload = (try? JSONSerialization.data(withJSONObject: ["site": startURL.absoluteString,
            "name": name, "mime": mime, "field": field ?? "", "base64": bytes.base64EncodedString()]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        view.evaluateJavaScript("(() => { const __input = \(payload); const site = __input.site, name = __input.name,\n" +
            "mime = __input.mime, field = __input.field, base64 = __input.base64;\n" + script + "\n})()") { result, _ in
            completion(result as? String ?? "page unavailable")
        }
    }

    private static let mimeTypes: [String: String] = [
        "pdf": "application/pdf", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml", "txt": "text/plain",
        "csv": "text/csv", "json": "application/json", "xml": "application/xml", "zip": "application/zip",
        "gz": "application/gzip", "tar": "application/x-tar", "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "mp3": "audio/mpeg", "wav": "audio/wav", "mp4": "video/mp4", "mov": "video/quicktime",
        "webm": "video/webm", "ics": "text/calendar",
    ]

    private static let script = #"""
    if (!['http:', 'https:'].includes(location.protocol) || location.origin !== new URL(site).origin)
        return 'wrong site origin';
    // Custom upload buttons often have a hidden file input. Include it, but never guess between inputs.
    const normalize = s => (s || '').trim().replace(/\s+/gu, ' ');
    const wanted = normalize(field);
    const roots = [document]; let input;
    for (const root of roots) {
        for (const el of root.querySelectorAll('*')) {
            if (el.shadowRoot) roots.push(el.shadowRoot);
            if (!el.matches('input[type=file]')) continue;
            if (wanted) {
                const labels = Array.from(el.labels || [], l => l.textContent);
                labels.push(el.getAttribute('aria-label'));
                const refs = (el.getAttribute('aria-labelledby') || '').trim().split(/\s+/u);
                labels.push(refs.map(id => root.getElementById(id)?.textContent || '').join(' '));
                if (!labels.some(s => normalize(s) === wanted)) continue;
            }
            if (input) return wanted ? 'ambiguous field' : 'multiple file inputs';
            input = el;
        }
    }
    if (!input) return wanted ? 'field not found' : 'no file input';
    if (input.matches(':disabled') || input.closest('[inert],[aria-disabled="true"]')) return 'control disabled';
    if (input.webkitdirectory) return 'directory input unsupported';
    const types = input.accept.toLowerCase().split(',').map(x => x.trim()).filter(Boolean);
    if (types.length && !types.some(t => t === mime || t === '*/*' || (t.startsWith('.') && name.toLowerCase().endsWith(t)) ||
        (t.endsWith('/*') && mime.startsWith(t.slice(0, -1))))) return 'file type not accepted';
    const raw = atob(base64), bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    const selection = new DataTransfer();
    selection.items.add(new File([bytes], name, { type: mime }));
    input.files = selection.files;
    input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    return 'ok';
    """#
}
