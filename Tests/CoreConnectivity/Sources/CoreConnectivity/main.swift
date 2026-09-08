import NotiflyCore

let result = UserIdTransitionPolicy.shared.evaluate(
    previousUserId: nil,
    newUserId: "connectivity-check"
)

_ = result
