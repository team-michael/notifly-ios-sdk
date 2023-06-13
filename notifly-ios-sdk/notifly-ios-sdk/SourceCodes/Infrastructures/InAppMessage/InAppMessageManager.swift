//
//  InAppMessageManager.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

class InAppMessageManager {
    private var userData: UserData = UserData(userProperties: [:])
    private var campaginData: CampaignData = CampaignData(inAppMessageCampaigns: [])
    private var eventData: EventData = EventData(eventCounts: [])
    
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
                            let a = self.constructCampaign(campaignData: campaignData)
                            print(a.count)
                        }

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
    
    private func updateUserProperties(properties: [String: Any]) {
        self.userData.userProperties.merge(properties) { (_, new) in new }
        Logger.error("SUC, ")
        print(self.userData.userProperties)
    }
    
    private func constructCampaign(campaignData: [[String:Any]]) -> [Campaign] {
        
        return campaignData.compactMap { campaignDict -> Campaign? in
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
    
}



