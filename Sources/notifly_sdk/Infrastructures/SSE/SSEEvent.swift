//
//  SSEEvent.swift
//  notifly-ios-sdk
//
// Represents one event from the WHATWG Server-Sent Events stream format.
//

import Foundation

struct SSEEvent: Equatable {

    let id: String?
    let type: String
    let data: String
}
