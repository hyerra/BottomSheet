//
//  Copyright © FINN.no AS, Inc. All rights reserved.
//

import UIKit

// MARK: - Public extensions

extension CGFloat {
    public static let bottomSheetAutomatic: CGFloat = -123456789
}

// MARK: - Delegate

public protocol BottomSheetViewDelegate: AnyObject {
    func bottomSheetViewDidReachDismissArea(_ view: BottomSheetView)
}

// MARK: - View

public final class BottomSheetView: UIView {
    public weak var delegate: BottomSheetViewDelegate?

    public var isDimViewHidden: Bool {
        get { dimView.isHidden }
        set { dimView.isHidden = newValue }
    }

    // MARK: - Private properties

    private let contentView: UIView
    private let targetHeights: [CGFloat]
    private var topConstraint: NSLayoutConstraint!
    private var targetOffsets = [CGFloat]()
    private var thresholds = [CGFloat]()
    private var currentTargetOffsetIndex: Int = 0
    private var currentTargetOffset: CGFloat {
        return targetOffsets[currentTargetOffsetIndex]
    }

    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(panGesture:)))
    private lazy var springAnimator = SpringAnimator(dampingRatio: 0.8, frequencyResponse: 0.4)

    private lazy var handleView: UIView = {
        let view = UIView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .handle
        view.layer.cornerRadius = 2
        return view
    }()

    private lazy var dimView: UIView = {
        let view = UIView(frame: .zero)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = UIColor(white: 0, alpha: 0.4)
        view.isHidden = true
        view.alpha = 0
        return view
    }()

    // MARK: - Init

    public init(contentView: UIView, targetHeights: [CGFloat]) {
        self.contentView = contentView
        self.targetHeights = targetHeights.isEmpty ? [.bottomSheetAutomatic] : targetHeights
        super.init(frame: .zero)
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    // MARK: - Overrides

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Make shadow to be on top
        let rect = CGRect(x: 0, y: 0, width: bounds.width, height: 30)
        layer.shadowPath = UIBezierPath(rect: rect).cgPath
    }

    // MARK: - Public API

    /// Presents bottom sheet view from the bottom of the given container view.
    ///
    /// - Parameters:
    ///   - view: the container for the bottom sheet view
    ///   - completion: a closure to be executed when the animation ends
    public func present(in superview: UIView, targetIndex: Int = 0, completion: ((Bool) -> Void)? = nil) {
        guard self.superview != superview else { return }

        superview.addSubview(dimView)
        superview.addSubview(self)

        translatesAutoresizingMaskIntoConstraints = false
        dimView.frame = superview.bounds
        topConstraint = topAnchor.constraint(equalTo: superview.topAnchor, constant: superview.frame.height)

        springAnimator.addAnimation { [weak self] position in
            self?.topConstraint.constant = position.y
            self?.updateDimViewAlpha(for: position.y)
        }

        springAnimator.addCompletion { didComplete in completion?(didComplete) }

        NSLayoutConstraint.activate([
            topConstraint,
            bottomAnchor.constraint(greaterThanOrEqualTo: superview.bottomAnchor),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor)
        ])

        superview.layoutIfNeeded()
        addGestureRecognizer(panGesture)

        updateTargetOffsets()
        transition(to: targetIndex)
    }

    /// Animates bottom sheet view out of the screen bounds and removes it from the superview on completion.
    ///
    /// - Parameters:
    ///   - completion: a closure to be executed when the animation ends
    public func dismiss(completion: ((Bool) -> Void)? = nil) {
        springAnimator.addCompletion { [weak self] didComplete in
            if didComplete {
                self?.dimView.removeFromSuperview()
                self?.removeFromSuperview()
            }

            completion?(didComplete)
        }

        animate(to: superview?.frame.height ?? 0)
    }

    /// Recalculates target offsets and animates to the minimum one.
    /// Call this method e.g. when orientation change is detected.
    public func reset() {
        updateTargetOffsets()
        animate(to: currentTargetOffset)
    }

    /// Animates bottom sheet view to the given height.
    ///
    /// - Parameters:
    ///   - index: the index of the target height
    public func transition(to index: Int) {
        guard index >= 0 && index < targetHeights.count else {
            assertionFailure("Provided index is out of bounds of the array with target heights.")
            return
        }
        guard let offset = offset(from: targetHeights[index]) else { return }
        animate(to: offset)
    }

    // MARK: - Setup

    private func setup() {
        clipsToBounds = true
        backgroundColor = contentView.backgroundColor

        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = .zero
        layer.shadowRadius = 3
        layer.rasterizationScale = UIScreen.main.scale
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        addSubview(contentView)
        addSubview(handleView)

        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            handleView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            handleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 25),
            handleView.heightAnchor.constraint(equalToConstant: 4),

            contentView.topAnchor.constraint(equalTo: handleView.bottomAnchor, constant: 8),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    // MARK: - Animations

    private func animate(to offset: CGFloat) {
        if let index = targetOffsets.firstIndex(of: offset) {
            currentTargetOffsetIndex = index
        }

        springAnimator.fromPosition = CGPoint(x: 0, y: topConstraint.constant)
        springAnimator.toPosition = CGPoint(x: 0, y: offset)
        springAnimator.initialVelocity = .zero
        springAnimator.startAnimation()
    }

    private func updateDimViewAlpha(for offset: CGFloat) {
        if let superview = superview, let maxOffset = targetOffsets.last {
            dimView.alpha = min(1, (superview.frame.height - offset) / (superview.frame.height - maxOffset))
        }
    }

    // MARK: - UIPanGestureRecognizer

    @objc private func handlePan(panGesture: UIPanGestureRecognizer) {
        let state = translationState(for: panGesture)

        switch panGesture.state {
        case .began:
            springAnimator.pauseAnimation()
        case .ended, .cancelled, .failed:
            animate(to: state.targetOffset)
            if state.isDismissible {
                delegate?.bottomSheetViewDidReachDismissArea(self)
            }
        default:
            break
        }

        topConstraint.constant = state.nextOffset
        updateDimViewAlpha(for: state.nextOffset)
        panGesture.setTranslation(.zero, in: superview)
    }

    // MARK: - Offset calculation

    private func translationState(for panGesture: UIPanGestureRecognizer) -> TranslationState {
        let lowerBound = currentTargetOffset - thresholds[currentTargetOffsetIndex]
        let upperBound = currentTargetOffset + thresholds[currentTargetOffsetIndex + 1]
        let currentArea = lowerBound ... upperBound
        let currentConstant = topConstraint.constant
        let translation = panGesture.translation(in: superview)
        let dragConstant = topConstraint.constant + translation.y

        if currentArea.contains(dragConstant) {
            // Within the area of the current target offset, allow dragging.
            return TranslationState(nextOffset: dragConstant, targetOffset: currentTargetOffset, isDismissible: false)
        } else if dragConstant < currentTargetOffset {
            let targetOffset = targetOffsets.first(where: { $0 < dragConstant })
            // Above the area of the current target offset, allow dragging if the next target offset is found.
            return TranslationState(
                nextOffset: targetOffset == nil ? currentConstant : dragConstant,
                targetOffset: targetOffset ?? currentTargetOffset,
                isDismissible: false
            )
        } else {
            let targetOffset = targetOffsets.first(where: { $0 > dragConstant })
            // Below the area of the current target offset,
            // allow dragging and set as dismissable if the next target offset is not found.
            return TranslationState(
                nextOffset: dragConstant,
                targetOffset: targetOffset ?? currentTargetOffset,
                isDismissible: targetOffset == nil
            )
        }
    }

    private func updateTargetOffsets() {
        targetOffsets = targetHeights.compactMap(offset(from:)).sorted()

        // Update thresholds
        let maxThreshold: CGFloat = 75
        thresholds = zip(targetOffsets.dropFirst(), targetOffsets).map { min(abs(($0 - $1) * 0.25), maxThreshold) }

        // First and last target offsets have equal botom and top thresholds
        if let first = thresholds.first, let last = thresholds.last {
            thresholds.insert(first, at: 0)
            thresholds.append(last)
        }
    }

    private func offset(from height: CGFloat) -> CGFloat? {
        guard let superview = superview else { return nil }

        let handleHeight: CGFloat = 20

        func makeTargetHeight() -> CGFloat {
            if height == .bottomSheetAutomatic {
                let size = contentView.systemLayoutSizeFitting(
                    superview.frame.size,
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
                return size.height + handleHeight
            } else {
                return height
            }
        }

        return max(superview.frame.height - makeTargetHeight(), handleHeight)
    }
}

private struct TranslationState {
    /// The offset to be set for the current pan gesture translation.
    let nextOffset: CGFloat
    /// The offset to be set when the pan gesture ended, cancelled or failed.
    let targetOffset: CGFloat
    /// A flag indicating whether the view is ready to be dismissed.
    let isDismissible: Bool
}

// MARK: - Private extensions

private extension UIColor {
    class var handle: UIColor {
        let defaultColor = UIColor(red: 195/255, green: 204/255, blue: 217/255, alpha: 1)

        if #available(iOS 13.0, *) {
            #if swift(>=5.1)
            return UIColor { traitCollection -> UIColor in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(red: 67/255, green: 67/255, blue: 89/255, alpha: 1)
                default:
                    return defaultColor
                }
            }
            #endif
        }

        return defaultColor
    }
}
