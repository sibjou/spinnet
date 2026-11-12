import Foundation

// MARK: - UserFacingError
// Текст ошибки для человека. Системные описания ошибок Firebase английские
// («The operation couldn't be completed…»), поэтому на экран идёт только наш русский текст.
enum UserFacingError {

    static let firestoreDomain = "FIRFirestoreErrorDomain"
    private static let unavailable = 14
    private static let deadlineExceeded = 4
    private static let permissionDenied = 7

    static func message(for error: Error, fallback: String) -> String {
        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            return "Нет связи с интернетом. Проверьте подключение и попробуйте ещё раз."
        }
        if ns.domain == firestoreDomain {
            switch ns.code {
            case unavailable, deadlineExceeded:
                return "Нет связи с сервером. Попробуйте чуть позже."
            case permissionDenied:
                return "Недостаточно прав для этого действия."
            default:
                break
            }
        }
        return fallback
    }
}
