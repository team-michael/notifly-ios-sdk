//
//  InAppMessageCancellationTests.swift
//  notifly-ios-sdkTests
//
//  Tests for in-app message cancellation feature:
//  - Campaign parsing of cancellation_conditions and cancellation_event_filters
//  - TriggeringConditions.match logic for cancellation events
//  - TriggeringEventFilter.matchFilterCondition for cancellation filters
//

import XCTest
@testable import notifly_ios_sdk

@available(iOSApplicationExtension, unavailable)
final class InAppMessageCancellationTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a valid campaign dictionary with all required fields.
    /// Optionally includes cancellation_conditions and cancellation_event_filters.
    private func makeCampaignDict(
        cancellationConditions: Any? = nil,
        cancellationEventFilters: Any? = nil,
        includeCancellationKeys: Bool = true
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": "test_campaign_1",
            "channel": "in-app-message",
            "status": 1,
            "testing": false,
            "updated_at": "2024-01-01T00:00:00Z",
            "starts": [1704067200],
            "end": NSNull(),
            "delay": 10,
            "segment_type": "condition",
            "segment_info": [
                "groups": [
                    ["conditions": [
                        [
                            "unit": "user",
                            "operator": "IS_NOT_NULL",
                            "attribute": "userId",
                            "useEventParamsAsConditionValue": false,
                            "valueType": "TEXT",
                            "value": ""
                        ]
                    ]]
                ]
            ],
            "message": [
                "html_url": "https://example.com/message",
                "modal_properties": [
                    "template_name": "test_template",
                    "position": "center"
                ]
            ],
            "triggering_conditions": [
                [["type": "event_name", "operator": "=", "operand": "purchase"]]
            ]
        ]

        if includeCancellationKeys {
            if let conditions = cancellationConditions {
                dict["cancellation_conditions"] = conditions
            }
            if let filters = cancellationEventFilters {
                dict["cancellation_event_filters"] = filters
            }
        }

        return dict
    }

    // MARK: - Campaign Parsing Tests

    /// Verify that Campaign correctly parses cancellation_conditions from a valid dictionary.
    func testCampaignParsesCancellationConditions() {
        let cancellationConditions: [[[String: Any]]] = [
            [["type": "event_name", "operator": "=", "operand": "cancel_event"]]
        ]
        let dict = makeCampaignDict(cancellationConditions: cancellationConditions)

        let campaign = Campaign(from: dict)

        XCTAssertNotNil(campaign, "Campaign should be parsed successfully from a valid dictionary")
        XCTAssertNotNil(campaign?.cancellationConditions, "cancellationConditions should not be nil when provided in the dictionary")
        XCTAssertEqual(campaign?.cancellationConditions?.conditions.count, 1, "There should be exactly one condition group")
    }

    /// Verify that Campaign correctly parses cancellation_event_filters from a valid dictionary.
    func testCampaignParsesCancellationEventFilters() {
        let cancellationConditions: [[[String: Any]]] = [
            [["type": "event_name", "operator": "=", "operand": "cancel_event"]]
        ]
        let cancellationEventFilters: [[[String: Any]]] = [
            [["key": "item_id", "operator": "=", "value": "abc", "value_type": "TEXT"]]
        ]
        let dict = makeCampaignDict(
            cancellationConditions: cancellationConditions,
            cancellationEventFilters: cancellationEventFilters
        )

        let campaign = Campaign(from: dict)

        XCTAssertNotNil(campaign, "Campaign should be parsed successfully from a valid dictionary")
        XCTAssertNotNil(campaign?.cancellationEventFilters, "cancellationEventFilters should not be nil when provided in the dictionary")
        XCTAssertEqual(campaign?.cancellationEventFilters?.filters.count, 1, "There should be exactly one filter group")
    }

    /// Verify that Campaign sets cancellation fields to nil when they are omitted from the dictionary.
    func testCampaignWithoutCancellationFields() {
        let dict = makeCampaignDict(includeCancellationKeys: false)

        let campaign = Campaign(from: dict)

        XCTAssertNotNil(campaign, "Campaign should still parse successfully without cancellation fields")
        XCTAssertNil(campaign?.cancellationConditions, "cancellationConditions should be nil when not provided")
        XCTAssertNil(campaign?.cancellationEventFilters, "cancellationEventFilters should be nil when not provided")
    }

    /// Verify that Campaign sets cancellation fields to nil when they are explicitly set to NSNull().
    func testCampaignWithNullCancellationFields() {
        let dict = makeCampaignDict(
            cancellationConditions: NSNull(),
            cancellationEventFilters: NSNull()
        )

        let campaign = Campaign(from: dict)

        XCTAssertNotNil(campaign, "Campaign should still parse successfully with NSNull cancellation fields")
        XCTAssertNil(campaign?.cancellationConditions, "cancellationConditions should be nil when set to NSNull")
        XCTAssertNil(campaign?.cancellationEventFilters, "cancellationEventFilters should be nil when set to NSNull")
    }

    // MARK: - TriggeringConditions.match Tests

    /// Verify that TriggeringConditions.match returns true when the event name matches a cancellation condition.
    func testTriggeringConditionsMatchesCancellationEvent() {
        let conditionsData: [[[String: Any]]] = [
            [["type": "event_name", "operator": "=", "operand": "cancel_event"]]
        ]

        let conditions = try? TriggeringConditions(from: conditionsData)

        XCTAssertNotNil(conditions, "TriggeringConditions should be created successfully")
        XCTAssertTrue(
            conditions!.match(eventName: "cancel_event"),
            "match should return true when the event name exactly matches the operand"
        )
    }

    /// Verify that TriggeringConditions.match returns false when the event name does not match.
    func testTriggeringConditionsDoesNotMatchDifferentEvent() {
        let conditionsData: [[[String: Any]]] = [
            [["type": "event_name", "operator": "=", "operand": "cancel_event"]]
        ]

        let conditions = try? TriggeringConditions(from: conditionsData)

        XCTAssertNotNil(conditions, "TriggeringConditions should be created successfully")
        XCTAssertFalse(
            conditions!.match(eventName: "purchase"),
            "match should return false when the event name does not match the operand"
        )
        XCTAssertFalse(
            conditions!.match(eventName: "cancel_event_extra"),
            "match should return false for a partial/extended event name"
        )
        XCTAssertFalse(
            conditions!.match(eventName: ""),
            "match should return false for an empty event name"
        )
    }

    /// Verify that TriggeringConditions.match works correctly when there are multiple condition groups (OR logic between groups).
    func testTriggeringConditionsMatchesMultipleGroups() {
        let conditionsData: [[[String: Any]]] = [
            [["type": "event_name", "operator": "=", "operand": "cancel_event_a"]],
            [["type": "event_name", "operator": "=", "operand": "cancel_event_b"]]
        ]

        let conditions = try? TriggeringConditions(from: conditionsData)

        XCTAssertNotNil(conditions, "TriggeringConditions should be created successfully with multiple groups")
        XCTAssertTrue(
            conditions!.match(eventName: "cancel_event_a"),
            "match should return true for the first condition group"
        )
        XCTAssertTrue(
            conditions!.match(eventName: "cancel_event_b"),
            "match should return true for the second condition group"
        )
        XCTAssertFalse(
            conditions!.match(eventName: "unrelated_event"),
            "match should return false for an event not in any condition group"
        )
    }

    // MARK: - TriggeringEventFilter.matchFilterCondition Tests

    /// Verify that TriggeringEventFilter.matchFilterCondition returns true when event params match the filter.
    func testTriggeringEventFilterMatchesParams() {
        let filterData: [[[String: Any]]] = [
            [["key": "item_id", "operator": "=", "value": "abc", "value_type": "TEXT"]]
        ]
        let filters = try? TriggeringEventFilters(from: filterData)

        XCTAssertNotNil(filters, "TriggeringEventFilters should be created successfully")

        let eventParams: [String: Any] = ["item_id": "abc"]
        let result = TriggeringEventFilter.matchFilterCondition(
            filters: filters!.filters,
            eventParams: eventParams
        )

        XCTAssertTrue(result, "matchFilterCondition should return true when event params match the filter")
    }

    /// Verify that TriggeringEventFilter.matchFilterCondition returns false when event params do not match the filter.
    func testTriggeringEventFilterDoesNotMatchDifferentParams() {
        let filterData: [[[String: Any]]] = [
            [["key": "item_id", "operator": "=", "value": "abc", "value_type": "TEXT"]]
        ]
        let filters = try? TriggeringEventFilters(from: filterData)

        XCTAssertNotNil(filters, "TriggeringEventFilters should be created successfully")

        let eventParamsDifferentValue: [String: Any] = ["item_id": "xyz"]
        XCTAssertFalse(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: eventParamsDifferentValue
            ),
            "matchFilterCondition should return false when the param value does not match"
        )

        let eventParamsMissingKey: [String: Any] = ["other_key": "abc"]
        XCTAssertFalse(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: eventParamsMissingKey
            ),
            "matchFilterCondition should return false when the expected key is missing from params"
        )

        XCTAssertFalse(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: nil
            ),
            "matchFilterCondition should return false when eventParams is nil"
        )

        XCTAssertFalse(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: [:]
            ),
            "matchFilterCondition should return false when eventParams is empty"
        )
    }

    /// Verify that TriggeringEventFilter.matchFilterCondition works with multiple filter groups (OR logic between groups).
    func testTriggeringEventFilterMatchesWithMultipleFilterGroups() {
        let filterData: [[[String: Any]]] = [
            [["key": "item_id", "operator": "=", "value": "abc", "value_type": "TEXT"]],
            [["key": "category", "operator": "=", "value": "electronics", "value_type": "TEXT"]]
        ]
        let filters = try? TriggeringEventFilters(from: filterData)

        XCTAssertNotNil(filters, "TriggeringEventFilters should be created successfully with multiple groups")

        // Matches first group
        let paramsMatchFirst: [String: Any] = ["item_id": "abc"]
        XCTAssertTrue(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: paramsMatchFirst
            ),
            "matchFilterCondition should return true when params match the first filter group"
        )

        // Matches second group
        let paramsMatchSecond: [String: Any] = ["category": "electronics"]
        XCTAssertTrue(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: paramsMatchSecond
            ),
            "matchFilterCondition should return true when params match the second filter group"
        )

        // Matches neither group
        let paramsMatchNeither: [String: Any] = ["item_id": "xyz", "category": "clothing"]
        XCTAssertFalse(
            TriggeringEventFilter.matchFilterCondition(
                filters: filters!.filters,
                eventParams: paramsMatchNeither
            ),
            "matchFilterCondition should return false when params match neither filter group"
        )
    }
}
