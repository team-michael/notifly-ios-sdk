/// Extracts the entitlements property list from a Mach-O code signature.
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
        guard let header: mach_header = binary.read() else { return nil }
        let commandCount = Int(header.ncmds)
        switch header.magic {
        case MH_MAGIC:
            return .singleArch(
                headerInfo: .init(
                    headerSize: MemoryLayout<mach_header>.size,
                    commandCount: commandCount
                )
            )
        case MH_MAGIC_64:
            return .singleArch(
                headerInfo: .init(
                    headerSize: MemoryLayout<mach_header_64>.size,
                    commandCount: commandCount
                )
            )
        default:
            binary.seek(to: 0)
            guard let fatHeader: fat_header = binary.read() else { return nil }
            return CFSwapInt32(fatHeader.magic) == FAT_MAGIC ? .fat(header: fatHeader) : nil
        }
    }

    private func readEntitlementsFromBinarySlice(startingAt offset: Int, cmdCount: Int) throws -> [String: Any] {
        binary.seek(to: UInt64(offset))
        for _ in 0..<cmdCount {
            guard let command: load_command = binary.read() else { break }
            guard command.cmdsize >= UInt32(MemoryLayout<load_command>.size) else { break }
            if command.cmd == LC_CODE_SIGNATURE {
                guard let sigOffset: UInt32 = binary.read() else {
                    throw Error.signatureReadingError
                }
                guard let sigSize: UInt32 = binary.read() else {
                    throw Error.signatureReadingError
                }
                return try readEntitlementsFromSignature(
                    startingAt: sigOffset,
                    signatureSize: sigSize
                )
            }
            let skip = UInt64(command.cmdsize) - UInt64(MemoryLayout<load_command>.size)
            binary.seek(to: binary.currentOffset + skip)
        }
        throw Error.codeSignatureCommandMissing
    }

    private func readEntitlementsFromSignature(startingAt offset: UInt32, signatureSize: UInt32) throws -> [String: Any] {
        let sigEnd = UInt64(offset) + UInt64(signatureSize)

        binary.seek(to: UInt64(offset))
        guard let metaBlob: CSSuperBlob = binary.read() else {
            throw Error.signatureReadingError
        }
        guard CFSwapInt32(metaBlob.magic) == CSMagic.embeddedSignature else {
            throw Error.signatureReadingError
        }

        let superBlobLength = CFSwapInt32(metaBlob.length)
        guard superBlobLength <= signatureSize else {
            throw Error.signatureReadingError
        }

        let metaBlobSize = UInt32(MemoryLayout<CSSuperBlob>.size)
        let blobSize = UInt32(MemoryLayout<CSBlob>.size)
        let itemCount = CFSwapInt32(metaBlob.count)

        for index in 0..<itemCount {
            let entryPos = UInt64(offset + metaBlobSize + index * blobSize)
            if let plist = readEntitlementsBlob(
                startingAt: entryPos,
                signatureOffset: offset,
                signatureEnd: sigEnd
            ) {
                return plist
            }
        }
        throw Error.signatureReadingError
    }

    private func readEntitlementsBlob(
        startingAt entryPos: UInt64,
        signatureOffset: UInt32,
        signatureEnd: UInt64
    ) -> [String: Any]? {
        guard entryPos + UInt64(MemoryLayout<CSBlob>.size) <= signatureEnd else { return nil }

        binary.seek(to: entryPos)
        guard let blob: CSBlob = binary.read() else { return nil }

        let blobOffset = CFSwapInt32(blob.offset)
        let blobPos = UInt64(signatureOffset) + UInt64(blobOffset)
        guard blobPos + 8 <= signatureEnd else { return nil }

        binary.seek(to: blobPos)
        guard let blobMagicRaw: UInt32 = binary.read() else { return nil }
        guard CFSwapInt32(blobMagicRaw) == CSMagic.embeddedEntitlements else { return nil }
        guard let lengthRaw: UInt32 = binary.read() else { return nil }
        let length = Int(CFSwapInt32(lengthRaw))
        guard length > 8 else { return nil }

        let dataLength = length - 8
        guard blobPos + UInt64(length) <= signatureEnd else { return nil }

        let data = binary.readData(ofLength: dataLength)
        guard data.count == dataLength else { return nil }

        return try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
    }
}
