import Foundation
import RealityKit
import ARKit

extension GeometrySource {
    func asArray<T>(ofType: T.Type) -> [T] {
        assert(MemoryLayout<T>.stride == stride, "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<count).map {
            buffer.contents()
                .advanced(by: offset + stride * Int($0))
                .assumingMemoryBound(to: T.self)
                .pointee
        }
    }

    func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}

extension GeometryElement {
    func asInt32Array() -> [Int32] {
        var data = [Int32]()
        let totalNumberOfInt32 = count * primitive.indexCount
        data.reserveCapacity(totalNumberOfInt32)

        for indexOffset in 0..<totalNumberOfInt32 {
            data.append(
                buffer.contents()
                    .advanced(by: indexOffset * MemoryLayout<Int32>.size)
                    .assumingMemoryBound(to: Int32.self)
                    .pointee
            )
        }

        return data
    }

    func asUInt32Array() -> [UInt32] {
        asInt32Array().map { UInt32($0) }
    }
}
