# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.6.3-beta.0] - 2026-08-22

### Fixed

- Limit forced FCM cached-token invalidation to beta SDK builds so stable builds keep normal token acquisition without a push-delivery gap.

## [2.6.2] - 2026-07-29

### Fixed

- Prevent background app wakes from opening SSE connections by checking application state immediately before each initial or reconnect attempt.

## [2.6.1] - 2026-07-13

### Fixed

- Prevent `session_start` internal events from being tracked unless the host app is in the foreground active state. This avoids recording background remote-notification/fetch process wakes as user-visible sessions.

## [2.6.1-beta.1] - 2026-06-17

### Fixed

- **FCM token refresh after cached-token invalidation.** The SDK now deletes Firebase Messaging's cached FCM registration token before requesting a replacement token, so beta builds do not keep re-registering a locally cached token that FCM already reports as `UNREGISTERED`.

## [2.6.0] - 2026-06-15

### Added

- **Ad push opt-out ("수신거부") action.** Push notifications carrying an `unsubscribe_url` custom-data field are treated as ad pushes and now expose a "수신거부" action on long-press; tapping it opens the `unsubscribe_url` (custom scheme deep link or web page). The SDK registers the `NOTIFLY_AD` notification category — merged with any categories the host app already registered — and handles the action tap. The cold-start case is covered: the tapped action identifier is cached so that, when the app is launched from a kill state by the opt-out tap, it navigates to the unsubscribe destination rather than the notification's content URL.
  - Requires the server to deliver ad pushes with `aps.category = "NOTIFLY_AD"` (alongside the `unsubscribe_url` custom data).

## [2.5.1] - 2026-06-10

### Fixed

- **APNs → FCM token acquisition ordering race on cold start.** The APNs token was assigned to Firebase Messaging on an async dispatch while the FCM token request was issued synchronously right after, so `Messaging.token(completion:)` could run before the APNs token was associated. This could register a stale/unassociated FCM token and drive repeated token re-acquisition. The APNs token assignment and the FCM token request now run within the same main-queue block, so the assignment is guaranteed to happen first (matching the ordering already used in the retry path).

## [2.5.0] - 2026-06-01

### Added

- **Real-time campaign data sync over SSE.**
  - Open a long-lived SSE channel from the SDK to Notifly server. When campaign state changes server-side (e.g. a new in-app message is triggered or a popup is updated), the SDK refreshes its local campaign data immediately instead of waiting for the next event-driven fetch.
  - On reconnect, the SDK sends `Last-Event-ID` so the server can replay popup entries that were missed during the disconnect window, recovering messages that fired while offline.
  - If the SSE channel cannot reach OPEN state within the fallback threshold, the SDK falls back to the legacy event-driven sync path automatically.

### Changed

- Reconnect backoff uses full jitter (100ms ~ 10s) across all attempts to disperse reconnect bursts after server-side disconnects such as rolling deploys.
- Reduce SSE verbose logging. Keep: `SSE connected`, `SSE disconnected`, `SSE sync received` plus error logs.

## [2.4.0] - 2026-04-14

### Added

- Support in-app browser mode for in-app message links: add `?nf_open_mode=in_app_browser` to open URLs in SFSafariViewController instead of an external browser.
- Automatic Universal Link detection via Mach-O entitlements parsing: URLs matching the app's associated domains are forwarded to the app's deep link handler via NSUserActivity.

## [2.3.1] - 2026-04-02

### Fixed

- Fix in-app popup display delay caused by asyncWorker blocking when device token is not yet available
- Improve thread safety of event count updates in UserStateManager

## [2.3.0] - 2026-02-25

### Added

- Support cancellation conditions for in-app message campaigns: scheduled popups can now be cancelled by subsequent events during the delay period.

## [2.2.0] - 2025-11-27

### Fixed

- Resolve race conditions between APNs/FCM token publisher, promise, and timeout, preventing rare runtime crashes
- Ensure consistent token state updates during APNs/FCM registration and eliminate duplicate completion paths

## [2.1.0] - 2025-11-13

### Fixed

- Fix in-app message WebView background transparency and dimming behavior for React Native New Architecture compatibility

## [2.0.0] - 2025-08-05

### Changed

- **BREAKING**: Update minimum deployment version to iOS 15.0+

## [1.17.3] - 2025-07-24

### Added

- Handle external user ID mismatch between database and SDK

## [1.17.2] - 2025-07-16

### Added

- Add `templateName` event params to in_app_message_show

## [1.17.1] - 2025-06-13

### Fixed

- Resolve APNs/FCM token timing issues with retry mechanism
- Remove duplicate FCM token request from PublicAPI initialize method
- Remove unnecessary try? keywords to eliminate compiler warnings

## [1.17.0] - 2025-04-16

### Added

- Support in-app message template with transparent background.

## [1.16.3] - 2025-04-01

### Fixed

- Change deployment targets to 13.0.

## [1.16.2] - 2025-03-25

### Fixed

- Fix Cocoapods minimum deployment target mismatch issue.

## [1.16.1] - 2025-03-14

### Changed

- Pass `link` event param to main_button_click event callback.

## [1.16.0] - 2025-03-10

### Added

- Added `addInAppMessageEventListener` to provide a interface to listen events from InAppMessage WebView.

## [1.15.0] - 2025-01-16

### Added

- Add `getNotiflyUserId()` method to get Notifly user ID.

## [1.14.2] - 2024-11-21

### Changed

- Update Firebase dependency version to 20.0.0.

## [1.14.1] - 2024-08-27

### Changed

- Change event tracking partition key to `notifly_device_id`.

## [1.14.0] - 2024-08-27

### Added

- Support for user metadata conditions (`user_id`, `random_bucket_number`) in in-app message campaigns.

## [1.13.1] - 2024-07-10

### Changed

- Open `NotiflyAnyCodable` to public.

## [1.13.0] - 2024-07-10

### Changed

- Change tracking event endpoint.

### Fixed

- Bug fixes for `AnyCodable` (Boolean).

## [1.12.1] - 2024-07-01

### Changed

- Change variable names for improved clarity.

## [1.12.0] - 2024-06-30

### Added

- Separate `PushExtension` SDK from `Notifly SDK` (`notifly_sdk_push_extension`).

## [1.11.0] - 2024-06-24

### Changed

- Update user state management logic using access queues.
- Replace user state locks with `NotiflyAsyncWorker` (Semaphore).

## [1.10.1] - 2024-06-20

### Fixed

- Fix main-thread checker warning.

## [1.10.0] - 2024-06-14

### Added

- Add `setTimezone`, `setPhoneNumber`, `setEmail` for convenience.
- Automatic tracking of the user's timezone for device properties.

## [1.9.0] - 2024-05-27

### Fixed

- Defend against crashes caused by concurrency issues during cancellable event storage.

## [1.8.0] - 2024-05-17

### Added

- Support advanced triggering conditions.
- Add custom headers to identify platform, SDK version, and SDK wrapper version.

## [1.7.1] - 2024-05-08

### Fixed

- Address crashes caused by concurrency issues while updating user event data.

## [1.7.0] - 2024-04-25

### Added

- Add privacy manifest.

## [1.6.1] - 2024-04-01

### Added

- Add `.list` option to default foreground push notification presentation options.

## [1.6.0] - 2024-03-13

### Fixed

- Perform additional validation before presenting in-app popups.

## [1.5.0] - 2024-03-06

### Added

- Track GCM message ID in Push Extension.
- Add urgent tracking events.

## [1.4.1] - 2024-03-06

### Removed

- Remove version dependency on `FirebaseMessaging`.

## [1.4.0] - 2024-01-18

### Added

- Support user segmentation with random bucket numbers and external user IDs.
- Support `IS_NULL` and `IS_NOT_NULL` operators in user segmentation.
- Add `TriggeringEventFilters` with event parameters.

### Fixed

- Make sync state tasks asynchronous.

## [1.3.0] - 2023-10-20

### Added

- Implement Push Extension as a SubSpec module.
- Add re-eligibility condition for campaigns.

### Fixed

- Various bug fixes.

## [1.2.1] - 2023-10-11

### Added

- Extend push notification capabilities.

## [1.2.0] - 2023-10-06

### Added

- Support re-eligibility conditions for in-app campaigns.

## [1.0.0] - 2023-05-26

### Added

- Initial release.
