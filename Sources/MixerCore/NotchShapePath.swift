import CoreGraphics

/// 화면 위 가장자리에 매달린 노치 실루엣: 위는 rect 전체 폭의 직선, 양쪽 위는 바깥으로 벌어지는 오목한 어깨,
/// 아래 두 모서리는 둥글다.
public enum NotchShapePath {
    public struct Metrics: Equatable {
        public let shoulder: CGFloat
        public let bottomRadius: CGFloat
    }

    public static func metrics(for size: CGSize) -> Metrics {
        let shoulder = max(0, min(8, size.height * 0.2, size.width * 0.1))
        let bottomRadius = max(0, min(20, size.height * 0.3, (size.width - shoulder * 2) / 2))
        return Metrics(shoulder: shoulder, bottomRadius: bottomRadius)
    }

    /// 크기와 관계없이 같은 순서·개수의 요소로 만들어 `CABasicAnimation(keyPath: "path")`로 보간할 수 있게 한다.
    public static func path(in rect: CGRect) -> CGPath {
        let metrics = metrics(for: rect.size)
        let s = metrics.shoulder
        let r = metrics.bottomRadius
        let left = rect.minX + s
        let right = rect.maxX - s
        let shoulderBottom = rect.maxY - s

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: shoulderBottom), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: right - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + r), control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: shoulderBottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
