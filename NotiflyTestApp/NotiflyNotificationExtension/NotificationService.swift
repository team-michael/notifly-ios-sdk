//
//  NotificationService.swift
//  test
//
//  Created by 김대성 on 2023/09/13.
//

import UserNotifications
import notifly_ios_sdk

class NotificationService: NotiflyNotificationServiceExtension {
    override init() {
        super.init()
        self.setup()
    }

    func setup() {
        self.register(projectId: TestConstant.projectID, username: TestConstant.username)
    }
}
