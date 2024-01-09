//
//  InAppMessage+Constant.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/06/12.
//

import Foundation

enum InAppMessageConstant {
    static let syncStateURL = "https://om97mq7cx4.execute-api.ap-northeast-2.amazonaws.com/default/notifly-js-sdk-user-state-retrieval"
    static let segmentInfoDefaultGroupOperator = "OR"
    static let segmentInfoDefaultConditionOperator = "AND"
    static let idSeparator = "~|~"
    static let injectedJavaScript = """
    const button_trigger = document.getElementById('notifly-button-trigger'); button_trigger.addEventListener('click', function(event){
    if (!event.notifly_button_click_type) return;
    window.webkit.messageHandlers.notiflyInAppMessageEventHandler.postMessage(JSON.stringify({
        type: event.notifly_button_click_type,
        button_name: event.notifly_button_name,
        link: event.notifly_button_click_link,
        extra_data: event.notifly_extra_data,
    }));
        });
    """
}
