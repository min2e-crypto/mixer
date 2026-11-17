import AppKit
import MixerCore
import QuartzCore
import SwiftUI

/// 노치 실루엣으로 마스크한 검정 캔버스. 실루엣 밖 클릭은 아래 창(메뉴바 등)으로 넘긴다.
final class NotchContainerView: NSView {
    var onCollapsedClick: (() -> Void)?

    private let maskLayer = CAShapeLayer()
    private let host: NSView
    private var expanded = false

    init(content: some View) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = maskLayer
        host.alphaValue = 0
        host.isHidden = true
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    /// 창 프레임이 바뀐 뒤 애니메이션 없이 실루엣을 맞춘다.
    func setShape(_ rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = bounds
        maskLayer.path = NotchShapePath.path(in: rect)
        CATransaction.commit()
    }

    func animateShape(from: CGRect, to: CGRect, expanding: Bool, completion: @escaping () -> Void) {
        expanded = expanding
        let fromPath = NotchShapePath.path(in: from)
        let toPath = NotchShapePath.path(in: to)

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        maskLayer.frame = bounds
        maskLayer.path = toPath
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = fromPath
        animation.toValue = toPath
        animation.duration = expanding ? 0.3 : 0.22
        animation.timingFunction = CAMediaTimingFunction(name: expanding ? .easeOut : .easeIn)
        maskLayer.add(animation, forKey: "path")
        CATransaction.commit()

        if expanding { host.isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanding ? 0.25 : 0.15
            host.animator().alphaValue = expanding ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.expanded else { return }
                self.host.isHidden = true
            }
        }
    }

    func collapseImmediately() {
        expanded = false
        maskLayer.removeAllAnimations()
        host.alphaValue = 0
        host.isHidden = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard maskLayer.path?.contains(local) == true else { return nil }
        guard expanded else { return self }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        if !expanded { onCollapsedClick?() }
    }
}
