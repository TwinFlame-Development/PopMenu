//
//  PopMenuViewController.swift
//  PopMenu
//
//  Created by Cali Castle on 4/12/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import UIKit

/// Delegate for handling PopMenu selection.
@objc public protocol PopMenuViewControllerDelegate: class {
    /// Called when an action is selected.
    @objc optional func popMenuDidSelectItem(_ popMenuViewController: PopMenuViewController, at index: Int)
}

final public class PopMenuViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Delegate instance for handling callbacks.
    public weak var delegate: PopMenuViewControllerDelegate?
    
    /// Appearance configuration.
    public var appearance = PopMenuAppearance()
    
    /// Background overlay that covers the whole screen.
    public let backgroundView = UIView()
    
    /// The blur overlay view for translucent illusion.
    private lazy var blurOverlayView: UIVisualEffectView = {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = appearance.popMenuCornerRadius
        blurView.layer.masksToBounds = true
        blurView.isUserInteractionEnabled = false
        
        return blurView
    }()
    
    /// Main root view that has shadows.
    public let containerView = UIView()
    
    /// Main content view.
    public let contentView = PopMenuGradientView()
    
    /// The view contains all the actions.
    public let actionsView = UIStackView()
    
    /// Holds the actions, so every one of them can be reached when the menu is shorter than they
    /// are: always for a long menu, and for a short one when its view hasn't room for it.
    fileprivate let actionsScrollView = UIScrollView()
    
    /// The source View to be displayed from.
    private(set) weak var sourceView: AnyObject?
    
    /// The source view's frame in this menu's view, read again each time the menu is laid out
    /// (`layoutMenu()`). Until the menu is on screen it is the frame in the source view's window.
    private(set) var absoluteSourceFrame: CGRect?
    
    /// The calculated content frame.
    public lazy var contentFrame: CGRect = {
        return calculateContentFittingFrame()
    }()
    
    // MARK: - Configurations
    
    /// Determines whether to dismiss menu after an action is selected.
    public var shouldDismissOnSelection: Bool = true
    
    /// Determines whether the pan gesture is enabled on the actions.
    public var shouldEnablePanGesture: Bool = true
    
    /// Determines whether enable haptics for iPhone 7 and up.
    public var shouldEnableHaptics: Bool = true
    
    /// Handler for when the menu is dismissed.
    public var didDismiss: ((Bool) -> Void)?
    
    // MARK: - Constraints
    
    private(set) var contentLeftConstraint: NSLayoutConstraint!
    private(set) var contentTopConstraint: NSLayoutConstraint!
    private(set) var contentWidthConstraint: NSLayoutConstraint!
    private(set) var contentHeightConstraint: NSLayoutConstraint!
    
    /// The UIView instance of source view. Looked up each time: the system may move a bar button
    /// item's view, or replace it, while the menu is open.
    fileprivate var sourceViewAsUIView: UIView? {
        guard let sourceView = sourceView else { return nil }
        
        // Check if UIBarButtonItem
        if let sourceBarButtonItem = sourceView as? UIBarButtonItem {
            if let buttonView = sourceBarButtonItem.value(forKey: "view") as? UIView {
                return buttonView
            }
        }
        
        if let sourceView = sourceView as? UIView {
            return sourceView
        }
        
        return nil
    }
    
    /// What the menu was last laid out for: its view's size and safe area, and its source view's
    /// frame. Nil until it is presented. A change in any of them lays the menu out again.
    fileprivate var laidOutState: LayoutState?
    
    fileprivate struct LayoutState: Equatable {
        let size: CGSize
        let safeArea: UIEdgeInsets
        let sourceFrame: CGRect?
    }
    
    /// Space kept between the menu and the edges of the area it may use.
    fileprivate let edgeMargin: CGFloat = 8
    
    /// Tap gesture to dismiss for background view.
    fileprivate lazy var tapGestureForDismissal: UITapGestureRecognizer = {
        let tapper = UITapGestureRecognizer(target: self, action: #selector(backgroundViewDidTap(_:)))
        tapper.cancelsTouchesInView = false
        tapper.delaysTouchesEnded = false
        
        return tapper
    }()
    
    /// Pan gesture to highligh actions.
    fileprivate lazy var panGestureForMenu: UIPanGestureRecognizer = {
        let panner = UIPanGestureRecognizer(target: self, action: #selector(menuDidPan(_:)))
        panner.maximumNumberOfTouches = 1
        
        return panner
    }()
    
    /// Actions of menu.
    public private(set) var actions: [PopMenuAction] = []
    
    /// Max content width allowed for the content to stretch to: 90% of the area the menu may use.
    fileprivate var maxContentWidth: CGFloat {
        return layoutArea.width * 0.9
    }
    
    /// Where the menu may go: this view's bounds less its safe area. The menu is sized and placed
    /// from the view it is presented in, never from the device's screen, which can differ from it
    /// (a foldable's other display, an iPad window, Split View).
    fileprivate var layoutArea: CGRect {
        if #available(iOS 11.0, *) {
            return view.bounds.inset(by: view.safeAreaInsets)
        }
        return view.bounds
    }
    
    // MARK: - View Life Cycle
    
    /// PopMenuViewController constructor
    ///
    /// - Parameters:
    ///   - sourceView: the source view for triggering the menu
    ///   - actions: all the menu actions
    ///   - appearance: appearance configuration
    public convenience init(sourceView: AnyObject? = nil, actions: [PopMenuAction], appearance: PopMenuAppearance? = nil) {
        self.init(nibName: nil, bundle: nil)
        
        self.sourceView = sourceView
        self.actions = actions

        // Assign appearance or use the default one.
        if let appearance = appearance {
            self.appearance = appearance
        }

        setAbsoluteSourceFrame()
        
        transitioningDelegate = self
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }
    
    /// Load view entry point.
    public override func loadView() {
        super.loadView()

        view.backgroundColor = .clear
        
        configureBackgroundView()
        configureContentView()
        configureActionsView()
    }
    
    /// Set the source frame: in this menu's view once the menu is on screen, and in the source view's
    /// window before that. With no source view on screen there is none, and the menu is centred.
    fileprivate func setAbsoluteSourceFrame() {
        absoluteSourceFrame = currentSourceFrame()
    }
    
    /// The source view's frame as it is now (see `setAbsoluteSourceFrame()`).
    fileprivate func currentSourceFrame() -> CGRect? {
        guard let sourceView = sourceViewAsUIView, sourceView.window != nil || !isViewLoaded else { return nil }
        if isViewLoaded, view.window != nil {
            return sourceView.convert(sourceView.bounds, to: view)
        }
        return sourceView.convert(sourceView.bounds, to: nil)
    }
    
    /// What the menu would be laid out for now.
    fileprivate var currentLayoutState: LayoutState {
        return LayoutState(size: view.bounds.size, safeArea: safeAreaInsetsOfView, sourceFrame: currentSourceFrame())
    }
    
    fileprivate var safeAreaInsetsOfView: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return view.safeAreaInsets
        }
        return .zero
    }
    
    /// Lay the menu out for its view as it is now: read the source view's frame again, fit the menu
    /// to this view, and update the constraints' constants (they are made once, in `loadView()`).
    func layoutMenu() {
        setAbsoluteSourceFrame()
        contentFrame = calculateContentFittingFrame()
        contentLeftConstraint.constant = contentFrame.origin.x
        contentTopConstraint.constant = contentFrame.origin.y
        contentWidthConstraint.constant = contentFrame.size.width
        contentHeightConstraint.constant = contentFrame.size.height
        // Scroll only when the actions don't all fit; then the pan that highlights them would fight it.
        actionsScrollView.isScrollEnabled = actionsScrollView.contentSize.height > contentFrame.size.height + 0.5
        panGestureForMenu.isEnabled = !actionsScrollView.isScrollEnabled
        laidOutState = currentLayoutState
    }
    
    /// Add a new action to the menu.
    ///
    /// - Parameter action: Action to be added
    public func addAction(_ action: PopMenuAction) {
        actions.append(action)
    }
    
    // MARK: - Status Bar Appearance
    
    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    /// Set status bar style.
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        // If style defined, return
        if let statusBarStyle = appearance.popMenuStatusBarStyle {
            return statusBarStyle
        }
        
        // Contrast of blur style
        let backgroundStyle = appearance.popMenuBackgroundStyle
        if let blurStyle = backgroundStyle.blurStyle {
            switch blurStyle {
            case .dark:
                return .lightContent
            default:
                return .default
            }
        }
        
        // Contrast of dimmed color
        if let dimColor = backgroundStyle.dimColor {
            return dimColor.blackOrWhiteContrastingColor() == .white ? .lightContent : .default
        }
        
        return .lightContent
    }
    
    /// Handle when device orientation changed or container size changed.
    ///
    /// - Parameters:
    ///   - size: Changed size
    ///   - coordinator: Coordinator that manages the container
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { context in
            self.layoutMenu()
            self.view.layoutIfNeeded()
        }, completion: { context in
            // The source view may only reach its new place once the transition has finished.
            self.layoutMenu()
            self.view.layoutIfNeeded()
        })
        
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    /// A change that comes without a transition coordinator is laid out here too: a new size, a new
    /// safe area, or a source view that has moved. Not while the menu is being presented or
    /// dismissed, so those animations run from and to their own frames.
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let laidOut = laidOutState, !isBeingPresented, !isBeingDismissed else { return }
        if laidOut != currentLayoutState {
            layoutMenu()
        }
    }
    
    @available(iOS 11.0, *)
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }
    
}

// MARK: - View Configurations

extension PopMenuViewController {
    
    /// Setup the background view at the bottom, once: pinned to this view's edges, so it covers the
    /// whole view at any size.
    fileprivate func configureBackgroundView() {
        backgroundView.backgroundColor = .clear
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addGestureRecognizer(tapGestureForDismissal)
        backgroundView.isUserInteractionEnabled = true
        
        let backgroundStyle = appearance.popMenuBackgroundStyle
        
        // Blurred background
        if let isBlurred = backgroundStyle.isBlurred,
            isBlurred,
            let blurStyle = backgroundStyle.blurStyle {
            
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            blurView.translatesAutoresizingMaskIntoConstraints = false
            
            backgroundView.addSubview(blurView)
            NSLayoutConstraint.activate([
                blurView.leftAnchor.constraint(equalTo: backgroundView.leftAnchor),
                blurView.rightAnchor.constraint(equalTo: backgroundView.rightAnchor),
                blurView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
                blurView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
            ])
        }
        
        // Dimmed background
        if let isDimmed = backgroundStyle.isDimmed,
            isDimmed,
            let color = backgroundStyle.dimColor,
            let opacity = backgroundStyle.dimOpacity {
            
            backgroundView.backgroundColor = color.withAlphaComponent(opacity)
        }
        
        view.insertSubview(backgroundView, at: 0)
        NSLayoutConstraint.activate([
            backgroundView.leftAnchor.constraint(equalTo: view.leftAnchor),
            backgroundView.rightAnchor.constraint(equalTo: view.rightAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    /// Setup the content view.
    fileprivate func configureContentView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addShadow(offset: .init(width: 0, height: 1), opacity: 0.5, radius: 20)
        containerView.layer.cornerRadius = appearance.popMenuCornerRadius
        containerView.backgroundColor = .clear
        
        view.addSubview(containerView)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.cornerRadius = appearance.popMenuCornerRadius
        contentView.layer.masksToBounds = true
        contentView.clipsToBounds = true
        
        let colors = appearance.popMenuColor.backgroundColor.colors
        if colors.count > 0 {
            if colors.count == 1 {
                // Configure solid fill background.
                contentView.backgroundColor = colors.first?.withAlphaComponent(0.9)
                contentView.startColor = .clear
                contentView.endColor = .clear
            } else {
                // Configure gradient color.
                contentView.diagonalMode = true
                contentView.startColor = colors.first!
                contentView.endColor = colors.last!
                contentView.gradientLayer.opacity = 0.8
            }
        }

        containerView.addSubview(blurOverlayView)
        containerView.addSubview(contentView)
        
        setupContentConstraints()
    }
    
    /// Activate necessary constraints. Called once; a later layout changes their constants
    /// (`layoutMenu()`).
    fileprivate func setupContentConstraints() {
        contentLeftConstraint = containerView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: contentFrame.origin.x)
        contentTopConstraint = containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: contentFrame.origin.y)
        contentWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: contentFrame.size.width)
        contentHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: contentFrame.size.height)
        
        // Activate container view constraints
        NSLayoutConstraint.activate([
            contentLeftConstraint,
            contentTopConstraint,
            contentWidthConstraint,
            contentHeightConstraint
        ])
        // Activate content view constraints
        NSLayoutConstraint.activate([
            contentView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        // Activate blur overlay constraints
        NSLayoutConstraint.activate([
            blurOverlayView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            blurOverlayView.rightAnchor.constraint(equalTo: containerView.rightAnchor),
            blurOverlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurOverlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    /// Determine the fitting frame for content.
    ///
    /// - Returns: The fitting frame
    fileprivate func calculateContentFittingFrame() -> CGRect {
        var height: CGFloat
        
        if actions.count >= appearance.popMenuActionCountForScrollable {
            // Make scroll view
            height = CGFloat(appearance.popMenuActionCountForScrollable) * appearance.popMenuActionHeight
            height -= 20
        } else {
            height = CGFloat(actions.count) * appearance.popMenuActionHeight
        }
        // Never taller than the space there is: the actions scroll instead (`layoutMenu()`).
        height = min(height, max(0, verticalArea(for: absoluteSourceFrame).height - edgeMargin * 2))
        
        let size = CGSize(width: calculateContentWidth(), height: height)
        let origin = calculateContentOrigin(with: size)
        
        return CGRect(origin: origin, size: size)
    }
    
    /// Determine where the menu should display.
    ///
    /// - Returns: The source origin point
    fileprivate func calculateContentOrigin(with size: CGSize) -> CGPoint {
        guard let sourceFrame = absoluteSourceFrame else {
            // No source view (none given, or not on screen): centred in the space the menu may use,
            // which its height was fitted to.
            let area = layoutArea
            var origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            origin.y = min(origin.y, area.maxY - edgeMargin - size.height)
            origin.y = max(origin.y, area.minY + edgeMargin)
            return origin
        }
        // The menu may always reach as far as its source view, even where the source sits outside
        // the safe area (a bar button beside a camera housing, for example).
        let safe = layoutArea
        let minX = min(safe.minX, sourceFrame.minX), maxX = max(safe.maxX, sourceFrame.maxX)
        let area = CGRect(x: minX, y: safe.minY, width: maxX - minX, height: safe.height)
        let minContentPos: CGFloat = area.minX + area.width * 0.05
        let maxContentPos: CGFloat = area.maxX - area.width * 0.05
        
        // Get desired content origin point
        let offsetX = (size.width - sourceFrame.size.width ) / 2
        var desiredOrigin = CGPoint(x: sourceFrame.origin.x - offsetX, y: sourceFrame.origin.y)
        if (desiredOrigin.x + size.width) > maxContentPos {
            desiredOrigin.x = maxContentPos - size.width
        }
        if desiredOrigin.x < minContentPos {
            desiredOrigin.x = minContentPos
        }
        
        // Move content in place
        translateOverflowX(desiredOrigin: &desiredOrigin, contentSize: size)
        translateOverflowY(desiredOrigin: &desiredOrigin, contentSize: size)
        
        // Keep it inside the space it may use, top first: the height already fits it.
        let vertical = verticalArea(for: sourceFrame)
        desiredOrigin.y = min(desiredOrigin.y, vertical.maxY - edgeMargin - size.height)
        desiredOrigin.y = max(desiredOrigin.y, vertical.minY + edgeMargin)
        
        return desiredOrigin
    }
    
    /// The space the menu may use top to bottom: the safe area, stretched to reach the source view
    /// where it sits outside it.
    fileprivate func verticalArea(for sourceFrame: CGRect?) -> CGRect {
        let safe = layoutArea
        guard let source = sourceFrame else { return safe }
        let minY = min(safe.minY, source.minY), maxY = max(safe.maxY, source.maxY)
        return CGRect(x: safe.minX, y: minY, width: safe.width, height: maxY - minY)
    }
    
    /// Move content into view if it's overflowed in X axis.
    ///
    /// - Parameters:
    ///   - desiredOrigin: The desired origin point
    ///   - contentSize: Content size
    fileprivate func translateOverflowX(desiredOrigin: inout CGPoint, contentSize: CGSize) {
        let edgePadding: CGFloat = 8
        // Check content in left or right side
        let leftSide = (desiredOrigin.x - view.bounds.midX) < 0
        
        // Check view overflow
        let origin = CGPoint(x: leftSide ? desiredOrigin.x : desiredOrigin.x + contentSize.width, y: desiredOrigin.y)
        
        // Move accordingly
        if !view.bounds.contains(origin) {
            let overflowX: CGFloat = (leftSide ? 1 : -1) * ((leftSide ? view.bounds.minX : view.bounds.maxX) - origin.x) + edgePadding
            
            desiredOrigin = CGPoint(x: desiredOrigin.x - (leftSide ? -1 : 1) * overflowX, y: origin.y)
        }
    }
    
    /// Move content into view if it's overflowed in Y axis.
    ///
    /// - Parameters:
    ///   - desiredOrigin: The desired origin point
    ///   - contentSize: Content size
    fileprivate func translateOverflowY(desiredOrigin: inout CGPoint, contentSize: CGSize) {
        let edgePadding: CGFloat

        let origin = CGPoint(x: desiredOrigin.x, y: desiredOrigin.y + contentSize.height)

        if #available(iOS 11.0, *) {
            edgePadding = view.safeAreaInsets.bottom
        } else {
            edgePadding = 8
        }
        
        // Check content inside of view or not
        if !view.bounds.contains(origin) {
            let overFlowY: CGFloat = origin.y - view.bounds.maxY + edgePadding
            
            desiredOrigin = CGPoint(x: desiredOrigin.x, y: desiredOrigin.y - overFlowY)
        }
    }
    
    /// Determine the content width by the longest title possible.
    ///
    /// - Returns: The fitting width for content
    fileprivate func calculateContentWidth() -> CGFloat {
        var contentFitWidth: CGFloat = 0
        contentFitWidth += PopMenuDefaultAction.textLeftPadding * 2
        
        // Calculate the widest width from action titles to determine the width
        if let action = actions.max(by: {
            guard let title1 = $0.title, let title2 = $1.title else { return false }
            return title1.count < title2.count
        }) {
            let sizingLabel = UILabel()
            sizingLabel.text = action.title
            
            let desiredWidth = sizingLabel.sizeThatFits(view.bounds.size).width
            contentFitWidth += desiredWidth
            
            contentFitWidth += action.iconWidthHeight
        }
        
        return min(contentFitWidth,maxContentWidth)
    }
    
    /// Setup actions view.
    fileprivate func configureActionsView() {
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        actionsView.axis = .vertical
        actionsView.alignment = .fill
        actionsView.distribution = .fillEqually

        // Configure each action
        actions.forEach { action in
            action.font = appearance.popMenuFont
            action.tintColor = action.color ?? appearance.popMenuColor.actionColor.color
            action.cornerRadius = appearance.popMenuCornerRadius / 2
            action.renderActionView()
            
            // Give separator to each action but the last
            if !action.isEqual(actions.last) {
                addSeparator(to: action.view)
            }
            
            let tapper = UITapGestureRecognizer(target: self, action: #selector(menuDidTap(_:)))
            tapper.delaysTouchesEnded = false
            
            action.view.addGestureRecognizer(tapper)
            
            actionsView.addArrangedSubview(action.view)
        }
        
        // The actions sit in a scroll view either way, laid out as before: a long menu scrolls
        // always; a short one only when its view hasn't room for it (`layoutMenu()`), and keeps the
        // pan that highlights its actions otherwise.
        let scrollView = actionsScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = !appearance.popMenuScrollIndicatorHidden
        scrollView.indicatorStyle = appearance.popMenuScrollIndicatorStyle
        let actionsHeight = appearance.popMenuActionHeight * CGFloat(actions.count)
        scrollView.contentSize.height = actionsHeight
        
        scrollView.addSubview(actionsView)
        contentView.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        if actions.count >= (appearance.popMenuActionCountForScrollable) {
            // Scrollable actions
            NSLayoutConstraint.activate([
                actionsView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                actionsView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
                actionsView.topAnchor.constraint(equalTo: scrollView.topAnchor),
                actionsView.heightAnchor.constraint(equalToConstant: actionsHeight)
            ])
        } else {
            // Not scrollable while it fits
            actionsView.addGestureRecognizer(panGestureForMenu)
            
            NSLayoutConstraint.activate([
                actionsView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                actionsView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
                actionsView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
                actionsView.heightAnchor.constraint(equalToConstant: actionsHeight - 8)
            ])
        }
    }
    
    /// Add separator view for the given action view.
    ///
    /// - Parameters:
    ///   - separator: Separator style
    ///   - actionView: Action's view
    fileprivate func addSeparator(to actionView: UIView) {
        // Only setup separator if the style is neither 0 height or clear color
        guard appearance.popMenuItemSeparator != .none() else { return }
        
        let separator = appearance.popMenuItemSeparator
        
        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = separator.color
        
        actionView.addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            separatorView.leftAnchor.constraint(equalTo: actionView.leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: actionView.rightAnchor),
            separatorView.bottomAnchor.constraint(equalTo: actionView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: separator.height)
        ])
    }
    
}

// MARK: - Gestures Control

extension PopMenuViewController {

    /// Once the background view is tapped (for dismissal).
    @objc fileprivate func backgroundViewDidTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.isEqual(tapGestureForDismissal), !touchedInsideContent(location: gesture.location(in: view)) else { return }
        
        dismiss(animated: true) {
            // No selection made.
            self.didDismiss?(false)
        }
    }
    
    /// When the menu action gets tapped.
    @objc fileprivate func menuDidTap(_ gesture: UITapGestureRecognizer) {
        guard let attachedView = gesture.view, let index = actions.index(where: { $0.view.isEqual(attachedView) }) else { return }

        actionDidSelect(at: index)
    }
    
    /// When the pan gesture triggered in actions view.
    @objc fileprivate func menuDidPan(_ gesture: UIPanGestureRecognizer) {
        guard shouldEnablePanGesture else { return }
        
        switch gesture.state {
        case .began, .changed:
            if let index = associatedActionIndex(gesture) {
                let action = actions[index]
                // Must not be already highlighted
                guard !action.highlighted else { return }
                
                if shouldEnableHaptics {
                    Haptic.selection.generate()
                }
                
                // Highlight current action view.
                action.highlighted = true
                // Unhighlight other actions.
                actions.filter { return !$0.isEqual(action) }.forEach { $0.highlighted = false }
            }
        case .ended:
            // Unhighlight all actions.
            actions.filter { return $0.highlighted }.forEach { $0.highlighted = false }
            // Trigger action selection.
            if let index = associatedActionIndex(gesture) {
                actionDidSelect(at: index, animated: false)
            }
        default:
            return
        }
    }
    
    /// Check if touch is inside content view.
    fileprivate func touchedInsideContent(location: CGPoint) -> Bool {
        return containerView.frame.contains(location)
    }
    
    ///  Get the gesture associated action index.
    ///
    /// - Parameter gesture: Gesture recognizer
    /// - Returns: The index
    fileprivate func associatedActionIndex(_ gesture: UIGestureRecognizer) -> Int? {
        guard touchedInsideContent(location: gesture.location(in: view)) else { return nil }
        
        // Check which action is associated.
        let touchLocation = gesture.location(in: actionsView)
        // Get associated index for touch location.
        if let touchedView = actionsView.arrangedSubviews.filter({ return $0.frame.contains(touchLocation) }).first,
            let index = actionsView.arrangedSubviews.index(of: touchedView){
            return index
        }
        
        return nil
    }
    
    /// Triggers when an action is selected.
    ///
    /// - Parameter index: The index for action
    fileprivate func actionDidSelect(at index: Int, animated: Bool = true) {
        let action = actions[index]
        action.actionSelected?(animated: animated)
        
        if shouldEnableHaptics {
            // Generate haptics
            if #available(iOS 10.0, *) {
                Haptic.impact(.medium).generate()
            }
        }
        
        // Notify delegate
        delegate?.popMenuDidSelectItem?(self, at: index)
        
        // Should dismiss or not
        if shouldDismissOnSelection {
            dismiss(animated: true) {
                // Selection made.
                self.didDismiss?(true)
            }
        }
    }
    
}

// MARK: - Transitioning Delegate

extension PopMenuViewController: UIViewControllerTransitioningDelegate {
    
    /// Custom presentation animation.
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PopMenuPresentAnimationController(sourceFrame: absoluteSourceFrame)
    }
    
    /// Custom dismissal animation.
    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PopMenuDismissAnimationController(sourceFrame: absoluteSourceFrame)
    }

}
