# Changelog

All notable changes to this project will be documented in this file.  
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
