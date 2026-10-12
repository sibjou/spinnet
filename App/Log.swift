import Foundation

/// Отладочный вывод: в Release-сборке ничего не печатает и не вычисляет сообщение.
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
