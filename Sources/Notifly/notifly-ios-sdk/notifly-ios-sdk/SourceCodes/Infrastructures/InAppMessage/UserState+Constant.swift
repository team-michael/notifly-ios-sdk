import Foundation

//
//  InAppMessage.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//
@available(iOSApplicationExtension, unavailable)
enum UserStateConstant {
    static let syncStateLockTimeout = 5.0
    enum States {
        case campaignData(CampaignData)
        case userData(UserData)
        case eventData(EventData)
    }
}

@available(iOSApplicationExtension, unavailable)
struct UserData {
    var userProperties: [String: Any]
    var campaignHiddenUntil: [String: Int]
    var randomBucketNumber: Int?
    var platform: String
    var osVersion: String
    var appVersion: String?
    var sdkVersion: String?
    var sdkType: String
    var createdAt: TimeInterval?
    var updatedAt: TimeInterval?

    init(data: [String: Any]) {
        userProperties = (data["user_properties"] as? [String: Any]) ?? [:]
        campaignHiddenUntil = (data["campaign_hidden_until"] as? [String: Int]) ?? [:]
        platform = AppHelper.getDevicePlatform()
        osVersion = AppHelper.getiOSVersion()
        appVersion = AppHelper.getAppVersion()
        sdkVersion = NotiflyHelper.getSdkVersion()
        sdkType = NotiflyHelper.getSdkType()
        randomBucketNumber = NotiflyHelper.parseRandomBucketNumber(
            num: data["random_bucket_number"])
        if let createdAtStr = data["created_at"] as? String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            createdAt = dateFormatter.date(from: createdAtStr)?.timeIntervalSince1970
        }

        if let updatedAtStr = data["updated_at"] as? String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            updatedAt = dateFormatter.date(from: updatedAtStr)?.timeIntervalSince1970
        } else {
            updatedAt = TimeInterval(AppHelper.getCurrentTimestamp(unit: .second))
        }
    }

    func get(key: String) -> Any? {
        switch key {
        case "external_user_id":
            return try? Notifly.main.userManager.externalUserID
        case "platform":
            return platform
        case "os_version":
            return osVersion
        case "app_version":
            return appVersion
        case "sdk_version":
            return sdkVersion
        case "sdk_type":
            return sdkType
        case "created_at":
            return createdAt
        case "updated_at":
            return updatedAt
        case "random_bucket_number":
            return randomBucketNumber
        default:
            return nil
        }
    }

    static func merge(p1: UserData, p2: UserData) -> UserData {
        var mergedUserProperties: [String: Any] = [:]
        var mergedCampaignHiddenUntil: [String: Int] = [:]
        mergedUserProperties.merge(p2.userProperties) { _, new in new }
        mergedUserProperties.merge(p1.userProperties) { _, new in new }
        mergedCampaignHiddenUntil.merge(p2.campaignHiddenUntil) { _, new in new }
        mergedCampaignHiddenUntil.merge(p1.campaignHiddenUntil) { _, new in new }
        var data: [String: Any] = [
            "user_properties": mergedUserProperties,
            "campaign_hidden_until": mergedCampaignHiddenUntil
        ]

        data["platform"] = p1.platform
        data["os_version"] = p1.osVersion
        data["sdk_type"] = p1.sdkType
        if let appVersion = p1.appVersion ?? p2.appVersion {
            data["app_version"] = appVersion
        }
        if let sdkVersion = p1.sdkVersion ?? p2.sdkVersion {
            data["sdk_version"] = sdkVersion
        }
        data["random_bucket_number"] = p1.randomBucketNumber
        if let createdAt = p1.createdAt ?? p2.createdAt {
            data["created_at"] = createdAt
        }

        // updatedAt is always updated with current timestamp
        return UserData(data: data)
    }

    mutating func clear() {
        userProperties = [:]
        campaignHiddenUntil = [:]
        updatedAt = TimeInterval(AppHelper.getCurrentTimestamp(unit: .second))
    }

    func destruct() -> [String: Any] {
        var data: [String: Any] = [
            "user_properties": userProperties,
            "campaign_hidden_until": campaignHiddenUntil
        ]

        data["platform"] = platform
        data["os_version"] = osVersion
        data["sdk_type"] = sdkType
        data["random_bucket_number"] = randomBucketNumber
        if let appVersion = appVersion {
            data["app_version"] = appVersion
        }
        if let sdkVersion = sdkVersion {
            data["sdk_version"] = sdkVersion
        }

        if let createdAt = createdAt {
            data["created_at"] = createdAt
        }
        if let updatedAt = updatedAt {
            data["updated_at"] = updatedAt
        }
        return data
    }
}

@available(iOSApplicationExtension, unavailable)
struct CampaignData {
    var inAppMessageCampaigns: [Campaign]

    init(from: [[String: Any]]) {
        inAppMessageCampaigns = from.compactMap { Campaign(from: $0) }
    }
}

@available(iOSApplicationExtension, unavailable)
struct EventData {
    var eventCounts: [String: EventIntermediateCount]
    init(from: [[String: Any]]) {
        eventCounts =
            from
            .compactMap { EventIntermediateCount(from: $0) }
            .reduce(into: [String: EventIntermediateCount]()) { result, eventIntermediateCount in
                let id = EventIntermediateCount.generateId(
                    eventName: eventIntermediateCount.name,
                    eventParams: eventIntermediateCount.eventParams,
                    segmentationEventParamKeys: eventIntermediateCount.eventParams.keys.sorted(),
                    dt: eventIntermediateCount.dt)
                if var existingEventIntermediateCount = result[id] {
                    existingEventIntermediateCount.addCount(count: eventIntermediateCount.count)
                } else {
                    result[id] = eventIntermediateCount
                }
            }
    }

    init(eventCounts: [String: EventIntermediateCount]) {
        self.eventCounts = eventCounts
    }

    static func merge(p1: EventData, p2: EventData) -> EventData {
        var mergedEventCounts: [String: EventIntermediateCount] = p1.eventCounts
        for (id, eventIntermediateCount) in p2.eventCounts {
            if var existingEventIntermediateCount = mergedEventCounts[id] {
                existingEventIntermediateCount.addCount(count: eventIntermediateCount.count)
                mergedEventCounts[id] = existingEventIntermediateCount
            } else {
                mergedEventCounts[id] = eventIntermediateCount
            }
        }
        return EventData(eventCounts: mergedEventCounts)
    }

    mutating func clear() {
        eventCounts = [:]
    }
}

@available(iOSApplicationExtension, unavailable)
struct EventIntermediateCount {
    let name: String
    let dt: String
    var count: Int
    let eventParams: [String: Any]

    init?(from: [String: Any]) {
        guard let name = from["name"] as? String,
            let dt = from["dt"] as? String,
            let count = from["count"] as? Int,
            let eventParams = from["event_params"] as? [String: Any]
        else {
            return nil
        }
        self.name = name
        self.dt = dt
        self.count = count
        self.eventParams = eventParams
    }

    init(name: String, dt: String, count: Int, eventParams: [String: Any]) {
        self.name = name
        self.dt = dt
        self.count = count
        self.eventParams = eventParams
    }

    static func generateId(
        eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?,
        dt: String
    ) -> String {
        var eicID = eventName + InAppMessageConstant.eicIdSeparator + dt
        guard
            let selectedEventParams = EicHelper.selectEventParamsWithKeys(
                eventParams: eventParams, segmentationEventParamKeys: segmentationEventParamKeys),
            let (selectedKey, selectedValue) = selectedEventParams.first
        else {
            return eicID + String(repeating: InAppMessageConstant.eicIdSeparator, count: 2)
        }

        return eicID + InAppMessageConstant.eicIdSeparator + selectedKey
            + InAppMessageConstant.eicIdSeparator + selectedValue
    }

    mutating func addCount(count: Int) {
        self.count = self.count + count
    }
}

@available(iOSApplicationExtension, unavailable)
enum EicHelper {
    static func selectEventParamsWithKeys(
        eventParams: [String: Any]?, segmentationEventParamKeys: [String]?
    ) -> [String: String]? {
        if let segmentationEventParamKeys = segmentationEventParamKeys,
            let eventParams = eventParams,
            !segmentationEventParamKeys.isEmpty,
            eventParams.count > 0
        {
            let keyField = segmentationEventParamKeys[0]
            if let value = eventParams[keyField] as? String {
                return [keyField: value]
            }
        }
        return nil
    }
}

@available(iOSApplicationExtension, unavailable)
struct PostProcessConfigForSyncState {
    let merge: Bool
    let clear: Bool
}
