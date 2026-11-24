enum TokenState: Equatable {

    case pending
    case success
    case failed
    case retrying(attempt: Int)
}
