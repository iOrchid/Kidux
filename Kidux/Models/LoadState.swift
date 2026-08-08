import Foundation

/// SimpleNews 风格加载态（S17-01）
enum LoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case success(Value)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var value: Value? {
        if case .success(let value) = self { return value }
        return nil
    }
}
