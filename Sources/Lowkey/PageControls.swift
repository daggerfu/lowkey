import WebKit
import LowkeyCore

enum PageControls {
    static func run(_ command: PageCommand, args: [String], view: WKWebView, site: URL,
                    completion: @escaping (String) -> Void) {
        if command == .savePDF {
            run(.wait, args: [], view: view, site: site) { readiness in
                guard readiness == "ok" else { return completion(readiness == "pending" ? "page loading" : readiness) }
                guard args.count == 1 else { return completion("invalid") }
                PagePDF.save(view, to: URL(fileURLWithPath: args[0])) { error in
                    completion(error.map { "PDF export failed: \($0.localizedDescription)" } ?? "ok")
                }
            }
            return
        }
        // macOS 10.15 has no isolated content worlds: the script runs in the page's world.
        view.evaluateJavaScript(script(with: command, args: args, site: site)) { result, _ in
            completion(result as? String ?? "page unavailable")
        }
    }

    private static func script(with command: PageCommand, args: [String], site: URL) -> String {
        // The arguments are JSON-encoded, not string-interpolated: the page script parses them.
        let payload = (try? JSONSerialization.data(withJSONObject: ["cmd": command.rawValue, "args": args, "site": site.absoluteString],
                                                   options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "(() => { const __input = \(payload); const cmd = __input.cmd, args = __input.args, site = __input.site;\n" + scriptBody + "\n})()"
    }

    private static let scriptBody = #"""
    if (!['http:', 'https:'].includes(location.protocol) || location.origin !== new URL(site).origin) return 'wrong site origin';
    if (document.readyState === 'loading') return cmd === 'wait' ? 'pending' : 'page loading';
    if (cmd === 'wait' && !args.length) return 'ok';
    const norm = s => (s || '').trim().replace(/\s+/gu, ' ');
    const items = [], matches = [], roots = [document];
    for (const root of roots) for (const el of root.querySelectorAll('*')) {
        if (el.shadowRoot) roots.push(el.shadowRoot);
        let type;
        if (el.matches('button,[role=button],input[type=submit],input[type=button],input[type=reset]')) type = 'button';
        else if (el.matches('a[href],[role=link]')) type = 'link';
        else if (el.matches('select')) type = 'select';
        else if (el.matches('input[type=file]')) type = 'file';
        else if (el.matches('textarea') || (el instanceof HTMLInputElement && ['text','email','tel','url','search'].includes(el.type))) type = 'text';
        else continue;
        const visible = !!el.getClientRects().length && getComputedStyle(el).visibility === 'visible';
        if (!visible && type !== 'file') continue;
        const labels = [];
        const add = s => { s=norm(s); if (s && !labels.includes(s)) labels.push(s); };
        add(el.getAttribute('aria-label'));
        const ref = (el.getAttribute('aria-labelledby') || '').trim().split(/\s+/u);
        add(ref.map(id => root.getElementById(id)?.textContent || '').join(' '));
        for (const l of el.labels || []) {
            const clone = l.cloneNode(true); clone.querySelectorAll('input,textarea,select,button').forEach(n=>n.remove()); add(clone.textContent);
        }
        if (type === 'button' || type === 'link') add(el instanceof HTMLInputElement ? el.value : el.innerText);
        const disabled = el.matches(':disabled') || !!el.closest('[inert],[aria-disabled="true"]');
        if (cmd === 'inspect') {
            items.push({type, labels, disabled, visible});
            if (items.length > 2500) return 'inspection too large';
        } else if ((cmd !== 'fill' || type === 'text') && (cmd !== 'select' || type === 'select') && labels.includes(norm(args[0]))) {
            matches.push({el, disabled, visible});
            if (matches.length > 1) return 'ambiguous label';
        }
    }
    if (cmd === 'inspect') {
        const text = args[0] === '--json' ? JSON.stringify(items) : items.map(i=>i.type+'\t'+(i.labels.join(' / ') || '(unlabelled)')+(i.disabled?' [disabled]':'')).join('\n');
        return text.length <= 220000 ? 'output:'+text : 'inspection too large';
    }
    if (!matches.length) return cmd === 'wait' ? 'pending' : 'label not found';
    const {el, disabled, visible} = matches[0];
    if (disabled || !visible) return cmd === 'wait' ? 'pending' : 'control disabled';
    if (cmd === 'wait') return 'ok';
    if (cmd === 'fill') {
        if (el.readOnly) return 'control read only';
        el.value = args[1];
    } else if (cmd === 'select') {
        if (el.multiple) return 'multiple select unsupported';
        const options = Array.from(el.options).filter(o=>norm(o.label) === norm(args[1]));
        if (options.length !== 1) return options.length ? 'ambiguous option' : 'option not found';
        if (options[0].matches(':disabled')) return 'control disabled';
        el.selectedIndex = options[0].index;
    } else return 'invalid';
    el.dispatchEvent(new Event('input',{bubbles:true,composed:true}));
    el.dispatchEvent(new Event('change',{bubbles:true}));
    return 'ok';
    """#
}
