//
//  MessageData.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/09/25.
//

import Foundation
import MobileCoreServices

struct PushAttachment {
    let attachmentType: AttachmentType
    let fileExtension: String
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
        self.attachmentType = attachmentType
        self.fileExtension = fileExtension
        self.url = url

        if attachmentType == .image {
            switch fileExtension {
            case "gif":
                attachmentFileType = kUTTypeGIF
            case "jpeg":
                attachmentFileType = kUTTypeJPEG
            default:
                attachmentFileType = kUTTypePNG
            }
        } else {
            switch fileExtension {
            case "avi":
                attachmentFileType = kUTTypeAVIMovie
            default:
                attachmentFileType = kUTTypeMPEG4
            }
        }
    }
}

enum AttachmentType: String {
    case image
    case video
}
