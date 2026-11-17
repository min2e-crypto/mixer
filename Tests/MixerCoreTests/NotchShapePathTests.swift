import CoreGraphics
import Testing
@testable import MixerCore

private func elementCount(_ path: CGPath) -> Int {
    var count = 0
    path.applyWithBlock { _ in count += 1 }
    return count
}

@Suite struct NotchShapePathTests {
    let rect = CGRect(x: 10, y: 20, width: 480, height: 220)

    @Test func path는_rect_안에_있다() {
        let bounds = NotchShapePath.path(in: rect).boundingBoxOfPath
        #expect(bounds.minX >= rect.minX - 0.001)
        #expect(bounds.maxX <= rect.maxX + 0.001)
        #expect(bounds.minY >= rect.minY - 0.001)
        #expect(bounds.maxY <= rect.maxY + 0.001)
    }

    @Test func 위_가장자리는_rect_전체_폭이다() {
        let path = NotchShapePath.path(in: rect)
        #expect(path.contains(CGPoint(x: rect.minX + 2, y: rect.maxY - 0.05)))
        #expect(path.contains(CGPoint(x: rect.maxX - 2, y: rect.maxY - 0.05)))
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func 어깨와_아래_모서리는_비어_있다() {
        let path = NotchShapePath.path(in: rect)
        #expect(!path.contains(CGPoint(x: rect.minX + 0.5, y: rect.midY)))
        #expect(!path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.midY)))
        let inset = NotchShapePath.metrics(for: rect.size).shoulder
        #expect(!path.contains(CGPoint(x: rect.minX + inset + 0.5, y: rect.minY + 0.5)))
        #expect(!path.contains(CGPoint(x: rect.maxX - inset - 0.5, y: rect.minY + 0.5)))
    }

    @Test func 좌우_대칭이다() {
        let path = NotchShapePath.path(in: rect)
        for y in stride(from: rect.minY + 0.5, to: rect.maxY, by: 7) {
            for dx in stride(from: CGFloat(0.5), to: rect.width / 2, by: 3) {
                #expect(path.contains(CGPoint(x: rect.minX + dx, y: y)) == path.contains(CGPoint(x: rect.maxX - dx, y: y)))
            }
        }
    }

    @Test func 곡률은_크기에_비례해_제한된다() {
        let small = NotchShapePath.metrics(for: CGSize(width: 197, height: 32))
        let large = NotchShapePath.metrics(for: CGSize(width: 480, height: 220))
        #expect(small.shoulder <= 32 * 0.25)
        #expect(small.bottomRadius <= 32 / 2)
        #expect(large.shoulder >= small.shoulder)
        #expect(large.bottomRadius >= small.bottomRadius)
        #expect(large.shoulder * 2 + large.bottomRadius * 2 <= 480)
    }

    @Test func 크기가_달라도_요소_수가_같아_path_애니메이션이_된다() {
        #expect(elementCount(NotchShapePath.path(in: CGRect(x: 141, y: 188, width: 197, height: 32))) == elementCount(NotchShapePath.path(in: rect)))
    }

    @Test func 크기가_0이어도_멈추지_않는다() {
        _ = NotchShapePath.path(in: CGRect(x: 0, y: 0, width: 0, height: 0))
        _ = NotchShapePath.path(in: CGRect(x: 0, y: 0, width: 4, height: 2))
    }
}
