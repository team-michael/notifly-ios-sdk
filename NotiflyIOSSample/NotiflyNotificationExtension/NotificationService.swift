//
//  NotificationService.swift
//  NotiflyNotificationExtension
//
//  Created by Minkyu Cho on 4/19/25.
//

import notifly_sdk
import UserNotifications

class NotificationService: NotiflyNotificationServiceExtension {
    override init() {
        super.init()
        self.setup()
    }

    func setup() {
        self.register(projectId: "b80c3f0e2fbd5eb986df4f1d32ea2871", username: "minyong")
    }
}
