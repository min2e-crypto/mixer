import CoreGraphics

/// NSScreen에서 뽑은 값. AppKit 화면 좌표(왼쪽 아래 원점)다.
public struct NotchScreen: Equatable, Sendable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?
    public var scale: CGFloat

    public init(frame: CGRect, safeAreaTop: CGFloat, auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?, scale: CGFloat) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.scale = scale
    }
}

public struct NotchGeometry: Equatable, Sendable {
    public static let defaultExpandedSize = CGSize(width: 480, height: 220)
    static let wing: CGFloat = 6

    public let camera: CGRect
    public let collapsed: CGRect
    public let expanded: CGRect

    public init?(screen: NotchScreen, expandedSize: CGSize = defaultExpandedSize) {
        guard let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight else { return nil }
        let width = right.minX - left.maxX
        let height = screen.safeAreaTop
        guard width > 0, height > 0 else { return nil }

        let scale = max(screen.scale, 1)
        let top = screen.frame.maxY
        camera = CGRect(x: left.maxX, y: top - height, width: width, height: height)

        let collapsedWidth = Self.snap(width + Self.wing * 2, scale)
        collapsed = CGRect(
            x: Self.snap(camera.midX - collapsedWidth / 2, scale),
            y: Self.snap(top - height, scale),
            width: collapsedWidth,
            height: Self.snap(height, scale))

        let expandedWidth = Self.snap(min(expandedSize.width, screen.frame.width), scale)
        let expandedHeight = Self.snap(min(expandedSize.height, screen.frame.height), scale)
        let centeredX = min(max(camera.midX - expandedWidth / 2, screen.frame.minX), screen.frame.maxX - expandedWidth)
        expanded = CGRect(
            x: Self.snap(centeredX, scale),
            y: Self.snap(top - expandedHeight, scale),
            width: expandedWidth,
            height: expandedHeight)
    }

    /// 펼친 창의 로컬 좌표에서 접힌 모양이 놓일 자리. 마스크 애니메이션의 시작·끝 rect다.
    public var collapsedInExpanded: CGRect {
        collapsed.offsetBy(dx: -expanded.minX, dy: -expanded.minY)
    }

    /// 1x 외장 모니터에서 0.5pt 좌표가 1px 흔들리지 않도록 물리 픽셀에 맞춘다.
    static func snap(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}
