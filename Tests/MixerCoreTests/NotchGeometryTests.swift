import CoreGraphics
import Testing
@testable import MixerCore

private let builtIn = NotchScreen(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 32,
    auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 665, height: 32),
    auxiliaryTopRight: CGRect(x: 850, y: 950, width: 662, height: 32),
    scale: 2)

@Suite struct NotchGeometryTests {
    @Test func 카메라_rect는_좌우_영역_사이다() throws {
        let geometry = try #require(NotchGeometry(screen: builtIn))
        #expect(geometry.camera == CGRect(x: 665, y: 950, width: 185, height: 32))
    }

    @Test func 노치가_없으면_nil이다() {
        var external = builtIn
        external.safeAreaTop = 0
        #expect(NotchGeometry(screen: external) == nil)
        external = builtIn
        external.auxiliaryTopLeft = nil
        #expect(NotchGeometry(screen: external) == nil)
        external = builtIn
        external.auxiliaryTopRight = CGRect(x: 600, y: 950, width: 912, height: 32)
        #expect(NotchGeometry(screen: external) == nil)
    }

    @Test func 접힌_프레임은_카메라보다_양옆으로_넓다() throws {
        let geometry = try #require(NotchGeometry(screen: builtIn))
        let collapsed = geometry.collapsed
        #expect(collapsed.width > geometry.camera.width)
        #expect(collapsed.minX - geometry.camera.minX == -(collapsed.maxX - geometry.camera.maxX))
        #expect(collapsed.maxY == builtIn.frame.maxY)
        #expect(collapsed.height == geometry.camera.height)
    }

    @Test func 펼친_프레임은_화면_위_가장자리_중앙에_매달린다() throws {
        let geometry = try #require(NotchGeometry(screen: builtIn, expandedSize: CGSize(width: 480, height: 220)))
        #expect(geometry.expanded == CGRect(x: 517.5, y: 762, width: 480, height: 220))
        #expect(geometry.expanded.midX == geometry.camera.midX)
    }

    @Test func 펼친_프레임은_화면보다_넓지_않다() throws {
        let geometry = try #require(NotchGeometry(screen: builtIn, expandedSize: CGSize(width: 3000, height: 220)))
        #expect(geometry.expanded.width <= builtIn.frame.width)
        #expect(geometry.expanded.minX >= builtIn.frame.minX)
    }

    @Test func 프레임을_배율에_맞춰_스냅한다() throws {
        var screen = builtIn
        screen.scale = 1
        screen.auxiliaryTopLeft = CGRect(x: 0, y: 950, width: 665.3, height: 32)
        let geometry = try #require(NotchGeometry(screen: screen, expandedSize: CGSize(width: 481, height: 220)))
        for rect in [geometry.collapsed, geometry.expanded] {
            for value in [rect.minX, rect.minY, rect.width, rect.height] {
                #expect(value == value.rounded())
            }
        }
        screen.scale = 2
        let retina = try #require(NotchGeometry(screen: screen, expandedSize: CGSize(width: 481, height: 220)))
        for value in [retina.expanded.minX, retina.collapsed.minX, retina.collapsed.width] {
            #expect((value * 2) == (value * 2).rounded())
        }
    }

    @Test func 펼친_창_안에서_접힌_rect는_위_가운데다() throws {
        let geometry = try #require(NotchGeometry(screen: builtIn))
        let local = geometry.collapsedInExpanded
        #expect(local.size == geometry.collapsed.size)
        #expect(local.maxY == geometry.expanded.height)
        #expect(local.minX + geometry.expanded.minX == geometry.collapsed.minX)
    }
}
