/// Mach-O 바이너리의 코드 서명에서 entitlements plist를 추출합니다.
/// Reference: https://github.com/matrejek/SwiftEntitlements
import Foundation
import MachO

class EntitlementsReader {

    enum Error: Swift.Error {
        case binaryOpeningError
        case unknownBinaryFormat
        case codeSignatureCommandMissing
        case signatureReadingError
        case unsupportedFatBinary
    }

    private struct CSSuperBlob {
        var magic: UInt32
        var length: UInt32
        var count: UInt32
    }

    private struct CSBlob {
        var type: UInt32
        var offset: UInt32
    }

    private struct CSMagic {
        static let embeddedSignature: UInt32 = 0xfade0cc0
        static let embeddedEntitlements: UInt32 = 0xfade7171
    }

    private struct BinaryHeaderData {
        let headerSize: Int
        let commandCount: Int
    }

    private enum BinaryType {
        case singleArch(headerInfo: BinaryHeaderData)
        case fat(header: fat_header)
    }

    private let binary: ApplicationBinary

    init(_ binaryPath: String) throws {
        guard let binary = ApplicationBinary(binaryPath) else {
            throw Error.binaryOpeningError
        }
        self.binary = binary
    }

    func readEntitlements() throws -> [String: Any] {
        switch getBinaryType() {
        case .singleArch(let headerInfo):
            return try readEntitlementsFromBinarySlice(
                startingAt: headerInfo.headerSize,
                cmdCount: headerInfo.commandCount
            )
        case .fat:
            throw Error.unsupportedFatBinary
        case .none:
            throw Error.unknownBinaryFormat
        }
    }

    private func getBinaryType(fromSliceStartingAt offset: UInt64 = 0) -> BinaryType? {
        binary.seek(to: offset)
        let header: mach_header = binary.read()
        let commandCount = Int(header.ncmds)
        switch header.magic {
        case MH_MAGIC:
            return .singleArch(headerInfo: .init(
                headerSize: MemoryLayout<mach_header>.size,
                commandCount: commandCount
            ))
        case MH_MAGIC_64:
            return .singleArch(headerInfo: .init(
                headerSize: MemoryLayout<mach_header_64>.size,
                commandCount: commandCount
            ))
        default:
            binary.seek(to: 0)
            let fatHeader: fat_header = binary.read()
            return CFSwapInt32(fatHeader.magic) == FAT_MAGIC ? .fat(header: fatHeader) : nil
        }
    }

    private func readEntitlementsFromBinarySlice(startingAt offset: Int, cmdCount: Int) throws -> [String: Any] {
        binary.seek(to: UInt64(offset))
        for _ in 0..<cmdCount {
            let command: load_command = binary.read()
            if command.cmd == LC_CODE_SIGNATURE {
                let signatureOffset: UInt32 = binary.read()
                return try readEntitlementsFromSignature(startingAt: signatureOffset)
            }
            binary.seek(to: binary.currentOffset + UInt64(command.cmdsize - UInt32(MemoryLayout<load_command>.size)))
        }
        throw Error.codeSignatureCommandMissing
    }

    private func readEntitlementsFromSignature(startingAt offset: UInt32) throws -> [String: Any] {
        binary.seek(to: UInt64(offset))
        let metaBlob: CSSuperBlob = binary.read()
        guard CFSwapInt32(metaBlob.magic) == CSMagic.embeddedSignature else {
            throw Error.signatureReadingError
        }

        let metaBlobSize = UInt32(MemoryLayout<CSSuperBlob>.size)
        let blobSize = UInt32(MemoryLayout<CSBlob>.size)
        let itemCount = CFSwapInt32(metaBlob.count)

        for index in 0..<itemCount {
            binary.seek(to: UInt64(offset + metaBlobSize + index * blobSize))
            let blob: CSBlob = binary.read()
            binary.seek(to: UInt64(offset + CFSwapInt32(blob.offset)))
            let blobMagic: UInt32 = CFSwapInt32(binary.read())
            if blobMagic == CSMagic.embeddedEntitlements {
                let length: UInt32 = CFSwapInt32(binary.read())
                let data = binary.readData(ofLength: Int(length) - 8)
                if let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any] {
                    return plist
                }
            }
        }
        throw Error.signatureReadingError
    }
}
