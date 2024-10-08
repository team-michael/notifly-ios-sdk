# 1.0.0

- Initial release.

# 1.2.0

- Feature: Re-Eligible Condition

# 1.2.1

- Feature: Push Extension

# 1.3.0

- Feature: Make Push Extension Module As SubSpec
- Feature:
- Fix: fix some bugs

# 1.4.0

- Feature: Support User Segmentation With Random Bucket Number And External User Id
- Feature: Support IS_NULL, IS_NOT_NULL operator As User Segmentation Operator
- Feature: Support TriggeringEventFilters With Event Params
- Fix: Make Sync State Tasks Asynchronous

# 1.4.1

- Chore: Remove version dependency on `FirebaseMessaging`

# 1.5.0

- Chore: Track GCM Message Id In Push Extension
- Feature: Urgent tracking event

# 1.6.0

- Fix: Additional Validation Before In App Popup Presented

# 1.6.1

- Chore: Add .list option to the default foreground push notification presentation options

# 1.7.0

- Chore: Add Privacy Manifest

# 1.7.1

- Fix: Defending against crashes due to concurrency issues in the process of updating the user's event data.

# 1.8.0

- Feature: Support advanced triggering conditions
- Feature: Add custom headers to identify platform and SDK version / SDK wrapper version

# 1.9.0

- Fix: Defending against crashes due to concurrency issues in the process of storing cancellable events.

# 1.10.0

- Feature: Add `setTimezone`, `setPhoneNumber`, `setEmail` for convenience.
- Feature: Now SDK automatically tracks the user's timezone for device property.

# 1.10.1

- Fix: Fix main-thread checker warning

# 1.11.0

- Chore: Change UserState Management Logic using access queue.
- Chore: Replace user state lock with NotiflyAsyncWorker (Semaphore)

# 1.12.0

- Chore: Separate PushExtension Sdk from Notifly SDK (notifly_sdk_push_extension)

# 1.12.1

- Chore: change variable name

# 1.13.0

- Chore: change tracking event endpoint
- Fix: fix bug for any codable (boolean)

# 1.13.1

- Chore: Open NotiflyAnyCodable to public

# 1.14.0

- Feat: Support User medata condition (user_id, random_bucket_number) for in-app-message campaign

# 1.14.1

- Chore: change event tracking partition key as notifly_device_id
