/// Receives an in-app message display or interaction event.
///
/// The first argument is the SDK event name. The second is an optional dictionary of
/// event attributes, such as `campaign_id`, `notifly_message_id`, `button_name`, or
/// `link`. Available keys depend on the event; read values with conditional casts.
///
/// Register listeners with `Notifly.addInAppMessageEventListener(listener:)` after
/// initialization. Callbacks execute synchronously on the event producer's thread,
/// and their return does not acknowledge delivery of the associated tracking event.
/// The SDK retains each registered closure until all listeners are removed or the
/// SDK instance is replaced. Capture owners weakly when appropriate.
public typealias InAppMessageEventListener = (String, [String: Any]?) -> Void
