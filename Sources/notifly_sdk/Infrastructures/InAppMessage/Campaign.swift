//
//  Campaign.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

@available(iOSApplicationExtension, unavailable)
struct Campaign {

    let id: String

    let triggeringConditions: TriggeringConditions
    let triggeringEventFilters: TriggeringEventFilters?

    let campaignStart: Int
    let campaignEnd: Int?
    let delay: Int
    let reEligibleCondition: NotiflyReEligibleConditionEnum.ReEligibleCondition?
    let cancellationConditions: TriggeringConditions?
    let cancellationEventFilters: TriggeringEventFilters?

    let testing: Bool
    let allowlist: [String]?

    let segmentType: NotiflySegmentation.SegmentationType
    let segmentInfo: NotiflySegmentation.SegmentInfo?

    let message: Message

    let updatedAt: String

    init?(from: [String: Any]) {
        guard let id = from["id"] as? String,
            let channel = from["channel"] as? String,
            channel == InAppMessageConstant.inAppMessageChannel,

            let triggeringConditions = try? TriggeringConditions(
                from: from["triggering_conditions"]
            ),

            let rawStatusValue = from["status"] as? Int,
            let campaignStatus = CampaignStatus(rawValue: rawStatusValue),
            campaignStatus == .active,

            let testing = from["testing"] as? Bool,

            let messageDict = from["message"] as? [String: Any],
            let htmlURL = messageDict["html_url"] as? String,
            let modalProperties = ModalProperties(
                properties: messageDict["modal_properties"] as? [String: Any]
            ),

            let rawSegmentType = from["segment_type"] as? String,
            let segmentType = NotiflySegmentation.SegmentationType(rawValue: rawSegmentType),
            segmentType == .conditionBased,
            let segmentInfoDict = from["segment_info"] as? [String: Any],

            let updatedAt = from["updated_at"] as? String
        else {
            return nil
        }

        self.id = id

        self.triggeringConditions = triggeringConditions
        triggeringEventFilters = try? TriggeringEventFilters(from: from["triggering_event_filters"])

        let campaignStarts: [Int] = (from["starts"] as? [Int]) ?? []
        campaignStart = !campaignStarts.isEmpty ? campaignStarts[0] : 0
        campaignEnd = from["end"] as? Int
        delay = (from["delay"] as? Int) ?? 0
        reEligibleCondition = NotiflyReEligibleConditionEnum.ReEligibleCondition(
            from: from["re_eligible_condition"] as? [String: Any]
        )
        cancellationConditions = try? TriggeringConditions(from: from["cancellation_conditions"])
        cancellationEventFilters = try? TriggeringEventFilters(from: from["cancellation_event_filters"])

        self.testing = testing
        allowlist = testing ? from["whitelist"] as? [String] : []

        self.segmentType = segmentType
        segmentInfo = NotiflySegmentation.SegmentInfo(from: segmentInfoDict)

        message = Message(
            htmlURL: htmlURL,
            modalProperties: modalProperties,
            templateRenderingMode: messageDict["template_rendering_mode"] as? String
        )

        self.updatedAt = updatedAt
    }
}

@available(iOSApplicationExtension, unavailable)
enum CampaignStatus: Int {

    case invalid = -1
    case draft = 0
    case active = 1
    case inactive = 2
    case completed = 3
}

@available(iOSApplicationExtension, unavailable)
struct Message {

    let htmlURL: String
    let modalProperties: ModalProperties
    let templateRenderingMode: String?
}

@available(iOSApplicationExtension, unavailable)
struct ModalProperties {

    let templateName: String
    let position: String?
    let width: CGFloat?
    let min_width: CGFloat?
    let max_width: CGFloat?
    let width_vw: CGFloat?
    let width_vh: CGFloat?
    let height: CGFloat?
    let min_height: CGFloat?
    let max_height: CGFloat?
    let height_vw: CGFloat?
    let height_vh: CGFloat?
    let borderBottomLeftRadius: CGFloat?
    let borderBottomRightRadius: CGFloat?
    let borderTopLeftRadius: CGFloat?
    let borderTopRightRadius: CGFloat?
    let backgroundOpacity: CGFloat?
    let dismissCTATapped: Bool?
    let backgroundColor: String?

    init?(properties: [String: Any]?) {
        guard let properties = properties else {
            return nil
        }
        guard let name = properties["template_name"] as? String else {
            return nil
        }

        templateName = name
        position = properties["position"] as? String

        func castPropertyToCGFloat(value: Any?) -> CGFloat? {
            return NotiflyValueComparator.castAnyToSpecifiedType(
                value: value,
                type: NotiflyValueType.cgFloat.rawValue
            ) as? CGFloat
        }

        width = castPropertyToCGFloat(value: properties["width"])
        min_width = castPropertyToCGFloat(value: properties["min_width"])
        max_width = castPropertyToCGFloat(value: properties["max_width"])
        width_vw = castPropertyToCGFloat(value: properties["width_vw"])
        width_vh = castPropertyToCGFloat(value: properties["width_vh"])
        height = castPropertyToCGFloat(value: properties["height"])
        min_height = castPropertyToCGFloat(value: properties["min_height"])
        max_height = castPropertyToCGFloat(value: properties["max_height"])
        height_vw = castPropertyToCGFloat(value: properties["height_vw"])
        height_vh = castPropertyToCGFloat(value: properties["height_vh"])
        borderBottomLeftRadius = castPropertyToCGFloat(value: properties["borderBottomLeftRadius"])
        borderBottomRightRadius = castPropertyToCGFloat(
            value: properties["borderBottomRightRadius"]
        )
        borderTopLeftRadius = castPropertyToCGFloat(value: properties["borderTopLeftRadius"])
        borderTopRightRadius = castPropertyToCGFloat(value: properties["borderTopRightRadius"])
        backgroundOpacity = castPropertyToCGFloat(value: properties["backgroundOpacity"])

        dismissCTATapped = (properties["dismissCTATapped"] ?? false) as? Bool
        backgroundColor = properties["backgroundColor"] as? String
    }

}

@available(iOSApplicationExtension, unavailable)
enum NotiflyReEligibleConditionEnum {

    enum Unit: String {

        case hour = "h"
        case day = "d"
        case week = "w"
        case month = "m"
        case infinite
    }

    struct ReEligibleCondition {

        let value: Int
        let unit: String

        init?(from: [String: Any]?) {
            guard let from = from else {
                return nil
            }
            guard let unit = from["unit"] as? String,
                let value = from["value"] as? Int
            else {
                return nil
            }
            self.value = value
            self.unit = unit
        }
    }

    static let defaultValue = -1
}
