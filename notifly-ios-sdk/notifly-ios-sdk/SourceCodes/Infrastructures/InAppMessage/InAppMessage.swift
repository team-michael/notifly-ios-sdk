//
//  InAppMessage.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

struct UserData {
    var userProperties: [String: Any]
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
}
