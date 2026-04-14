/// Mach-O 바이너리 파일을 읽기 위한 FileHandle 래퍼.
/// Reference: https://github.com/matrejek/SwiftEntitlements
import Foundation

class ApplicationBinary {

    private let handle: FileHandle

    init?(_ path: String) {
        guard let binaryHandle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        handle = binaryHandle
    }

    var currentOffset: UInt64 { handle.offsetInFile }

    func seek(to offset: UInt64) {
        handle.seek(toFileOffset: offset)
    }

    func read<T>() -> T {
        handle.readData(ofLength: MemoryLayout<T>.size).withUnsafeBytes { $0.load(as: T.self) }
    }

    func readData(ofLength length: Int) -> Data {
        handle.readData(ofLength: length)
    }

    deinit {
        handle.closeFile()
    }
}
