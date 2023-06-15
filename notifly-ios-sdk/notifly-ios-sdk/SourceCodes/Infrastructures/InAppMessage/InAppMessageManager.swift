//
//  InAppMessageManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation
import Combine


class InAppMessageManager {
    private var userData: UserData = UserData(userProperties: [:])
    private var campaginData: CampaignData = CampaignData(inAppMessageCampaigns: [])
    private var eventData: EventData = EventData(eventCounts: [:])
    
    private var _syncStateFinishedPub: AnyPublisher<Bool, Error>?
    private(set) var syncStateFinishedPub: AnyPublisher<Bool, Error>? {
        // TODO: Remove this temp workaround once APNs token is available.
        get {
            if let pub = _syncStateFinishedPub {
                return pub
                    .catch { _ in
                        Logger.error("FAIL TRACK EVENT!!")
                        return Just(false).setFailureType(to: Error.self)
                    }
                    .eraseToAnyPublisher()
            } else {
                Logger.error("FAIL TRACK EVENT")
                return Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
        }
        set {
            _syncStateFinishedPub = newValue
        }
    }
    private var syncStateFinishedPromise: Future<Bool, Error>.Promise?
    init() {
        syncStateFinishedPub = Future { [weak self] promise in
            self?.syncStateFinishedPromise = promise
            DispatchQueue.main.asyncAfter(deadline: .now() + (5.0)) {
                if let promise = self?.syncStateFinishedPromise {
                    Logger.error("FAIL nn")
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }.eraseToAnyPublisher()
    }

    func syncState() {
        guard let notifly = (try? Notifly.main) else {
            return
        }
        guard let projectID = notifly.projectID as String?,
              let notiflyUserID = (try? notifly.userManager.getNotiflyUserID()) else {
            Logger.error("Fail to sync user state because Notifly is not initalized yet.")
            return
        }
        
        requestSync(projectID: projectID, notiflyUserID: notiflyUserID) { result in
            switch result {
            case .success(let data):
                do{
                    if let decodedData = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let userData = decodedData["userData"] as? [String: Any],
                           let userProperties = userData["user_properties"] as? [String: Any] {
                            self.userData.userProperties = userProperties
                        }
                        
                        if let campaignData = decodedData["campaignData"] as? [[String: Any]] {
                            self.constructCampaignData(campaignData: campaignData)
                        }
                        
                        if let eicData = decodedData["eventIntermediateCountsData"] as? [[String: Any]] {
                            self.constructEventIntermediateCountsData(eicData: eicData)
                            print(self.eventData)
                        }
                        
                        try? Notifly.trackEvent(eventName: "HI1")
                        try? Notifly.trackEvent(eventName: "HI2", eventParams: ["kings": "kk", "KING": 2], segmentationEventParamKeys: ["KING"] )
                    } else {
                        Logger.error("Fail to sync user state")
                    }
                    
                } catch {
                    Logger.error(error.localizedDescription)
                }
            case .failure(let error):
                Logger.error(error.localizedDescription)
            }
            
           
        }
    }
    
    func requestSync(projectID: String, notiflyUserID: String, completion: @escaping (Result<Data, Error>) -> Void) {
        var urlComponents = URLComponents(string: InAppMessageConstant.syncStateURL)
        urlComponents?.queryItems = [
            URLQueryItem(name: "projectID", value: projectID),
            URLQueryItem(name: "notiflyUserID", value: notiflyUserID)
        ]
        
        if let url = urlComponents?.url {
            let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let data = data {
                        completion(.success(data))
                    } else {
                        let noDataError = NSError(domain: "No data received", code: 0, userInfo: nil)
                        completion(.failure(noDataError))
                    }
                } else {
                    let apiRequestError = NSError(domain: "API request failed", code: 0, userInfo: nil)
                    completion(.failure(apiRequestError))
                }
            }
            
            task.resume()
        } else {
            let invalidURLError = NSError(domain: "Invalid URL", code: 0, userInfo: nil)
            completion(.failure(invalidURLError))
        }
    }
    
    private func updateUserProperties(properties: [String: Any]) -> Void {
        self.userData.userProperties.merge(properties) { (_, new) in new }
    }
    
    func updateEventData(eventName: String, eventParams: [String: Any]?, segmentationEventParamKeys: [String]?) {
        let dt = self.getCurrentDate()
        var eicID = eventName + InAppMessageConstant.idSeparator + dt + InAppMessageConstant.idSeparator
        
        if let segmentationEventParamKeys = segmentationEventParamKeys,
           let eventParams = eventParams,
           segmentationEventParamKeys.count > 0,
           eventParams.count > 0,
           let keyField = segmentationEventParamKeys[0] as? String, // TODO: support multiple segmentationEventParamKey
           let value = eventParams[keyField] as? String,
           let valueStr = String(describing: value) as? String
        {
            eicID += keyField + InAppMessageConstant.idSeparator + valueStr
            self.updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [keyField: eventParams[keyField]])
        } else {
            eicID += InAppMessageConstant.idSeparator
            self.updateEventCountsInEventData(eicID: eicID, eventName: eventName, dt: dt, eventParams: [:])
        }
    }
    
    private func updateEventCountsInEventData(eicID: String, eventName: String, dt: String, eventParams: [String:Any]?) -> Void {
        if var eicToUpdate = self.eventData.eventCounts[eicID] as? EventIntermediateCount {
            eicToUpdate.count += 1
        } else {
            self.eventData.eventCounts[eicID] = EventIntermediateCount(name: eventName, dt: dt, count: 1, eventParams: (eventParams ?? [:]))
        }
        Logger.error("UPDATE")
        print(self.eventData.eventCounts)
    }
    
    private func constructCampaignData(campaignData: [[String:Any]]) -> Void {
        self.campaginData.inAppMessageCampaigns = campaignData.compactMap { campaignDict -> Campaign? in
            guard let id = campaignDict["id"] as? String,
                let testing = campaignDict["testing"] as? Bool,
                let triggeringEvent = campaignDict["triggering_event"] as? String,
                let statusRawValue = campaignDict["status"] as? Int,
                  let campaignStatus = CampaignStatus(rawValue: statusRawValue),
                let messageDict = campaignDict["message"] as? [String: Any],
                  let htmlURL = messageDict["html_url"] as? String,
                  let modalPropertiesDict = messageDict["modal_properties"] as? [String: Any],
                  let modalProperties = ModalProperties(properties: modalPropertiesDict),
                let segmentInfoDict = campaignDict["segment_info"] as? [String: Any],
                let channel = campaignDict["channel"] as? String,
                let segmentType = campaignDict["segment_type"] as? String,
                  channel == "in-app-message",
                  segmentType == "condition"
            else {
                return nil
            }
            
            let message = Message(htmlURL: htmlURL, modalProperties: modalProperties)
            
            var whitelist: [String]?
            if testing == true {
                guard let whiteList = campaignDict["whitelist"] as? [String] else {
                    return nil
                }
                whitelist = whiteList
            } else {
                whitelist = nil
            }
            
            var campaignStart: Int
            if let starts = campaignDict["starts"] as? [Int] {
                campaignStart = starts[0]
            } else {
                campaignStart = 0
            }
            let delay = campaignDict["delay"] as? Int
            let campaignEnd = campaignDict["end"] as? Int
            
            let segmentInfo = self.constructSegmnentInfo(segmentInfoDict: segmentInfoDict)

            return Campaign(id: id, channel: channel, segmentType: segmentType, message: message, segmentInfo: segmentInfo, triggeringEvent: triggeringEvent, campaignStart: campaignStart, campaignEnd: campaignEnd, delay: delay, status: campaignStatus, testing: testing, whitelist: whitelist)
            
        }
    }
    
    private func constructSegmnentInfo(segmentInfoDict: [String: Any]) -> SegmentInfo? {
        guard let rawGroups = segmentInfoDict["groups"] as? [[String: Any]], rawGroups.count > 0 else {
            return SegmentInfo(groups: nil, groupOperator: nil)
        }
        let groups = rawGroups.compactMap { groupDict -> Group? in
            guard let conditionDictionaries = groupDict["conditions"] as? [[String: Any]] else {
                    return nil
            }
            guard let conditions = conditionDictionaries.compactMap({ conditionDict -> Condition? in
                guard let unit = conditionDict["unit"] as? String else {
                    return nil
                }
                if unit == "event" {
                    guard let condition = try? EventBasedCondition(condition: conditionDict) else {
                        return nil
                    }
                    return .EventBasedCondition(condition)
                } else {
                    guard let condition = try? UserBasedCondition(condition: conditionDict) else {
                        print(conditionDict)
                        return nil
                    }
                    return .UserBasedCondition(condition)
                }
            }) as? [Condition] else {
                return nil
            }
            let conditionOperator = (groupDict["condition_operator"] as? String) ?? InAppMessageConstant.segmentInfoDefaultConditionOperator
            return Group(conditions: conditions.compactMap{ $0 }, conditionOperator: conditionOperator)
        }
        let groupOperator = segmentInfoDict["group_operator"] as? String ?? InAppMessageConstant.segmentInfoDefaultGroupOperator
        return SegmentInfo(groups: groups.compactMap{ $0 }, groupOperator: groupOperator)
    }
    
    private func constructEventIntermediateCountsData(eicData: [[String:Any]]) -> Void {
        guard eicData.count > 0 else {
            return
        }
        self.eventData.eventCounts = eicData.compactMap { eic -> (String, EventIntermediateCount)? in
            guard let name = eic["name"] as? String,
                  let dt = eic["dt"] as? String,
                  let countStr = eic["count"] as? String,
                  let count = Int(countStr),
                  let eventParams = eic["event_params"] as? [String: Any]
            else {
                return nil
            }
            var eicID = name + InAppMessageConstant.idSeparator + dt + InAppMessageConstant.idSeparator
            if eventParams.count > 0,
                let key = eventParams.keys.first,
                let value = eventParams.values.first,
                let valueStr = String(describing: value) as? String{
                eicID += key + InAppMessageConstant.idSeparator + valueStr
            } else {
                eicID += InAppMessageConstant.idSeparator
            }
            
            return (eicID, EventIntermediateCount(name: name, dt: dt, count: count, eventParams: eventParams))
        }.compactMap{ $0 }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    
    private func getCurrentDate() -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: currentDate)
    }
}
