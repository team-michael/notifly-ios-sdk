//
//  InAppMessage.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

struct UserData {
    var userProperties: [String: Any]
    var campaignHiddenUntil: [String: Int]
    var randomBucketNumber: Int?
    var platform: String?
    var osVersion: String?
    var appVersion: String?
    var sdkVersion: String?
    var sdkType: String?
    var createdAt: TimeInterval?
    var updatedAt: TimeInterval?

    init(data: [String: Any]) {
        userProperties = (data["user_properties"] as? [String: Any]) ?? [:]
        campaignHiddenUntil = (data["campaign_hidden_until"] as? [String: Int]) ?? [:]
        platform = data["platform"] as? String
        osVersion = data["os_version"] as? String
        appVersion = data["app_version"] as? String
        sdkVersion = data["sdk_version"] as? String
        sdkType = data["sdk_type"] as? String
        randomBucketNumber = data["random_bucket_number"] as? Int

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
            "campaign_hidden_until": mergedCampaignHiddenUntil,
        ]
        if let platform = p1.platform ?? p2.platform {
            data["platform"] = platform
        }
        if let osVersion = p1.osVersion ?? p2.osVersion {
            data["os_version"] = osVersion
        }
        if let appVersion = p1.appVersion ?? p2.appVersion {
            data["app_version"] = appVersion
        }
        if let sdkVersion = p1.sdkVersion ?? p2.sdkVersion {
            data["sdk_version"] = sdkVersion
        }
        if let sdkType = p1.sdkType ?? p2.sdkType {
            data["sdk_type"] = sdkType
        }
        if let randomBucketNumber = p1.randomBucketNumber ?? p2.randomBucketNumber {
            data["random_bucket_number"] = randomBucketNumber
        }
        if let createdAt = p1.createdAt ?? p2.createdAt {
            data["created_at"] = createdAt
        }

        // updatedAt is always updated with current timestamp
        return UserData(data: data)
    }

    mutating func clearUserData() {
        self.userProperties = [:]
        self.campaignHiddenUntil = [:]
        self.updatedAt = TimeInterval(AppHelper.getCurrentTimestamp(unit: .second))
    }
}

struct CampaignData {
    var inAppMessageCampaigns: [Campaign]
}

struct EventData {
    var eventCounts: [String: EventIntermediateCount]
}

struct EventIntermediateCount {
    let name: String
    let dt: String
    var count: Int
    let eventParams: [String: Any]
}

struct InAppMessageData {
    let notiflyMessageId: String
    let notiflyCampaignId: String
    let modalProps: ModalProperties
    let url: URL
    let deadline: DispatchTime
    let notiflyReEligibleCondition: ReEligibleCondition?
}
