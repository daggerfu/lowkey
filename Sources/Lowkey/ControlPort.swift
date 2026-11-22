import AppKit
import BobukCore
import LowkeyCore

/// The local control port of `lowkeyctl`: one BobukCore `MessagePortServer` per running copy,
/// named `ControlRequest.portName(pid:)`.
final class ControlPort {
    private let server: MessagePortServer

    init?(controller: AppController) {
        let name = ControlRequest.portName(pid: getpid())
        // CFMessagePort requires a synchronous reply. Only the serial IPC queue waits;
        // WebKit and the controller stay on the main queue, which must be free to receive replies.
        guard let server = MessagePortServer(name: name, queueLabel: "io.bobuk.lowkey.control", handler: { _, payload in
            guard let request = ControlRequest(payload: payload) else { return Data("invalid".utf8) }
            let deadline = DispatchTime.now() + .seconds(request.command.isPDFExport ? 60 : 4)
            return MessagePortServer.replyFromMainQueue(deadline: deadline, fallback: Data("result unknown".utf8)) { reply in
                controller.handle(request) { result in reply(Data(result.utf8)) }
            }
        }) else { return nil }
        self.server = server
    }
}
