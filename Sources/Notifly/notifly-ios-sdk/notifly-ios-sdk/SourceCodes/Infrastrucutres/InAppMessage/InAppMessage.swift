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
    var platform: String?
    var osVersion: String?
    var appVersion: String?
    var sdkVersion: String?
    var sdkType: String?
    var updatedAt: TimeInterval?

    init(data: [String: Any]) {
        let userProperties: [String: Any] = (data["user_properties"] as? [String: Any]) ?? [:]
        let campaignHiddenUntilData: [String: Int] = (data["campaign_hidden_until"] as? [String: Int]) ?? [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

        guard let platform = data["platform"] as? String,
              let osVersion = data["os_version"] as? String,
              let appVersion = data["app_version"] as? String,
              let sdkVersion = data["sdk_version"] as? String,
              let sdkType = data["sdk_type"] as? String,
              let updatedAtStr = data["updated_at"] as? String,
              let updatedAtDate = dateFormatter.date(from: updatedAtStr)
        else {
            self.userProperties = [:]
            self.campaignHiddenUntil = [:]
            return
        }
        
        self.userProperties = userProperties
        self.campaignHiddenUntil = campaignHiddenUntilData
        self.platform = platform
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.sdkType = sdkType
        updatedAt = updatedAtDate.timeIntervalSince1970
    }

    func get(key: String) -> Any? {
        switch key {
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
        case "updated_at":
            return updatedAt
        default:
            return nil
        }
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
