//
//  MessageData.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/09/25.
//

import Foundation
import UniformTypeIdentifiers

struct PushAttachment {

    let url: URL
    let attachmentFileType: CFString

    init(attachment: [String: Any]) throws {
        guard let rawAttatchmentType = attachment["attachment_type"] as? String,
            let fileExtension = attachment["file_extension"] as? String,
            let rawUrl = attachment["url"] as? String
        else {
            throw NotiflyError.unexpectedNil("The payload of push attachmnet is not valid.")
        }
        guard let attachmentType = AttachmentType(rawValue: rawAttatchmentType),
            let url = URL(string: rawUrl)
        else {
            throw NotiflyError.unexpectedNil("The payload of push attachmnet is not valid.")
        }
        self.url = url

        if attachmentType == .image {
            switch fileExtension {
            case "gif":
                attachmentFileType = UTType.gif.identifier as CFString
            case "jpeg":
                attachmentFileType = UTType.jpeg.identifier as CFString
            default:
                attachmentFileType = UTType.png.identifier as CFString
            }
        }
        else {
            switch fileExtension {
            case "avi":
                attachmentFileType = UTType.avi.identifier as CFString
            default:
                attachmentFileType = UTType.mpeg4Movie.identifier as CFString
            }
        }
    }
}

enum AttachmentType: String {

    case image
    case video
}
