import WebKit

enum PageClick {
    /// Evaluate in the main frame. Check the document origin and select and click
    /// synchronously in the same script, so navigation can't swap documents.
    /// macOS 10.15 has no isolated content worlds: the script runs in the page's world.
    static func perform(in webView: WKWebView, startURL: URL, label: String, completion: @escaping (String) -> Void) {
        let payload = (try? JSONSerialization.data(withJSONObject: ["site": startURL.absoluteString, "label": label]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        webView.evaluateJavaScript("(() => { const __input = \(payload); const site = __input.site, label = __input.label;\n" + script + "\n})()") { result, _ in
            completion(result as? String ?? "page unavailable")
        }
    }

    private static let script = #"""
    if (!['http:', 'https:'].includes(location.protocol) || location.origin !== new URL(site).origin)
        return 'wrong site origin';
    const normalize = s => (s || '').trim().replace(/\s+/gu, ' ');
    const wanted = normalize(label);
    const matches = [];
    const roots = [document];
    for (const root of roots) {
        for (const el of root.querySelectorAll('*')) {
            if (el.shadowRoot) roots.push(el.shadowRoot);
            if (!(el instanceof HTMLElement) || !el.matches('button,a[href],input[type=button],input[type=submit],input[type=reset],[role=button],[role=link]')) continue;
            if (!el.getClientRects().length || getComputedStyle(el).visibility !== 'visible') continue;
            const text = el instanceof HTMLInputElement ? el.value : el.innerText;
            if (![text, el.getAttribute('aria-label')].some(s => normalize(s) === wanted)) continue;
            matches.push(el);
            if (matches.length > 1) return 'ambiguous label';
        }
    }
    if (!matches.length) return 'label not found';
    const el = matches[0];
    if (el.matches(':disabled') || el.closest('[inert],[aria-disabled="true"]')) return 'control disabled';
    if (el instanceof HTMLAnchorElement && !['http:', 'https:'].includes(el.protocol)) return 'unsupported link';
    el.click();
    return 'ok';
    """#
}
