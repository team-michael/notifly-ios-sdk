//
//  SSEEvent.swift
//  notifly-ios-sdk
//
//  Server-Sent Events 스펙(WHATWG)에 따른 단일 이벤트 표현.
//

import Foundation

struct SSEEvent: Equatable {
    let id: String?
    let type: String
    let data: String
}
