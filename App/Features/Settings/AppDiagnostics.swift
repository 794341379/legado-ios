import Foundation
import MetricKit

final class AppDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = AppDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
        DiagnosticLog.shared.record(category: "应用", message: "启动 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                DiagnosticLog.shared.record(.error, category: "系统诊断", message: "崩溃诊断：\(String(decoding: crash.jsonRepresentation(), as: UTF8.self))")
            }
            for hang in payload.hangDiagnostics ?? [] {
                DiagnosticLog.shared.record(.warning, category: "系统诊断", message: "卡顿诊断：\(String(decoding: hang.jsonRepresentation(), as: UTF8.self))")
            }
        }
    }
}
