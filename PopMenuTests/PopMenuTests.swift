//
//  PopMenuTests.swift
//  PopMenuTests
//
//  Created by Cali Castle on 4/12/18.
//  Copyright © 2018 Cali Castle. All rights reserved.
//

import XCTest
@testable import PopMenu

/// The menu is laid out from the view it is presented in: its background covers that view after
/// every size change, it opens at its anchor wherever the anchor is when it is laid out, and a size
/// change updates its layout instead of adding to it. Presentation and size changes go through the
/// menu's own animator and `viewWillTransition(to:with:)`, with stand-in transition objects.
class PopMenuTests: XCTestCase {

    // MARK: Stand-ins for UIKit's transition objects

    final class TransitionContext: NSObject, UIViewControllerContextTransitioning {
        let containerView: UIView
        let menu: UIViewController
        init(containerView: UIView, menu: UIViewController) {
            self.containerView = containerView
            self.menu = menu
        }
        var isAnimated: Bool { return false }
        var isInteractive: Bool { return false }
        var transitionWasCancelled: Bool { return false }
        var presentationStyle: UIModalPresentationStyle { return .overFullScreen }
        func updateInteractiveTransition(_ percentComplete: CGFloat) {}
        func finishInteractiveTransition() {}
        func cancelInteractiveTransition() {}
        func pauseInteractiveTransition() {}
        func completeTransition(_ didComplete: Bool) {}
        func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { return key == .to ? menu : nil }
        func view(forKey key: UITransitionContextViewKey) -> UIView? { return key == .to ? menu.view : nil }
        var targetTransform: CGAffineTransform { return .identity }
        func initialFrame(for vc: UIViewController) -> CGRect { return .zero }
        func finalFrame(for vc: UIViewController) -> CGRect { return containerView.bounds }
    }

    /// Holds the blocks a view controller hands it, to run once the test has resized everything,
    /// as UIKit runs them inside the size-change animation.
    final class TransitionCoordinator: NSObject, UIViewControllerTransitionCoordinator {
        var alongside: [(UIViewControllerTransitionCoordinatorContext) -> Void] = []
        var completions: [(UIViewControllerTransitionCoordinatorContext) -> Void] = []
        let container: UIView
        init(container: UIView) { self.container = container }
        func animate(alongsideTransition animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
            if let animation = animation { alongside.append(animation) }
            if let completion = completion { completions.append(completion) }
            return true
        }
        func animateAlongsideTransition(in view: UIView?, animation: ((UIViewControllerTransitionCoordinatorContext) -> Void)?, completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)? = nil) -> Bool {
            return animate(alongsideTransition: animation, completion: completion)
        }
        func notifyWhenInteractionEnds(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
        func notifyWhenInteractionChanges(_ handler: @escaping (UIViewControllerTransitionCoordinatorContext) -> Void) {}
        func run() {
            alongside.forEach { $0(self) }
            completions.forEach { $0(self) }
        }
        var isAnimated: Bool { return false }
        var presentationStyle: UIModalPresentationStyle { return .overFullScreen }
        var initiallyInteractive: Bool { return false }
        var isInterruptible: Bool { return false }
        var isInteractive: Bool { return false }
        var isCancelled: Bool { return false }
        var transitionDuration: TimeInterval { return 0 }
        var percentComplete: CGFloat { return 1 }
        var completionVelocity: CGFloat { return 1 }
        var completionCurve: UIView.AnimationCurve { return .linear }
        func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? { return nil }
        func view(forKey key: UITransitionContextViewKey) -> UIView? { return nil }
        var containerView: UIView { return container }
        var targetTransform: CGAffineTransform { return .identity }
    }

    // MARK: Helpers

    /// A window holding a bar-like anchor 44 pt square, 16 pt in from the right, and a container the
    /// menu is presented in (the window itself unless `containerOffset` is given).
    final class Scene {
        let window: UIWindow
        let container: UIView
        let anchor: UIView
        let menu: PopMenuViewController
        init(size: CGSize, containerOffset: CGPoint? = nil, anchored: Bool = true, actions: Int = 4, appearance: PopMenuAppearance? = nil, safeAreaRight: CGFloat = 0) {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.isHidden = false
            if let offset = containerOffset {
                container = UIView(frame: CGRect(x: offset.x, y: offset.y, width: size.width - offset.x, height: size.height - offset.y))
                window.addSubview(container)
            } else {
                container = window
            }
            anchor = UIView()
            window.addSubview(anchor)
            let items = (0..<actions).map { PopMenuDefaultAction(title: "Menu item \($0)") as PopMenuAction }
            menu = PopMenuViewController(sourceView: anchored ? anchor : nil, actions: items, appearance: appearance)
            menu.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: safeAreaRight)
            placeAnchor()
            let context = TransitionContext(containerView: container, menu: menu)
            menu.animationController(forPresented: menu, presenting: UIViewController(), source: UIViewController())?.animateTransition(using: context)
            menu.view.layoutIfNeeded()
        }
        func placeAnchor() {
            anchor.frame = CGRect(x: window.bounds.width - 60, y: 40, width: 44, height: 44)
        }
        /// The window and container change size, the anchor moves with the bar, and the menu goes
        /// through `viewWillTransition(to:with:)` as UIKit drives it.
        func resize(to size: CGSize) {
            let coordinator = TransitionCoordinator(container: container)
            menu.viewWillTransition(to: size, with: coordinator)
            let offset = container === window ? CGPoint.zero : container.frame.origin
            window.frame = CGRect(origin: .zero, size: size)
            if container !== window {
                container.frame = CGRect(x: offset.x, y: offset.y, width: size.width - offset.x, height: size.height - offset.y)
            }
            menu.view.frame = container.bounds
            placeAnchor()
            menu.view.layoutIfNeeded()
            coordinator.run()
            menu.view.layoutIfNeeded()
        }
        /// The menu's frame and the anchor's, both in window coordinates.
        var menuFrame: CGRect { return menu.containerView.convert(menu.containerView.bounds, to: window) }
        var anchorFrame: CGRect { return anchor.convert(anchor.bounds, to: window) }
        var menuViewFrame: CGRect { return menu.view.convert(menu.view.bounds, to: window) }
    }

    /// The scroll view that holds the actions.
    func actionsScroll(_ menu: PopMenuViewController) -> UIScrollView? {
        return menu.contentView.subviews.compactMap { $0 as? UIScrollView }.first
    }

    /// Every action can be reached: the visible part plus what scrolls covers them all.
    func assertEveryActionReachable(_ scene: Scene, actions: Int, file: StaticString = #file, line: UInt = #line) {
        guard let scroll = actionsScroll(scene.menu) else { return XCTFail("the actions are in a scroll view", file: file, line: line) }
        let needed = scene.menu.appearance.popMenuActionHeight * CGFloat(actions)
        XCTAssertEqual(scroll.contentSize.height, needed, accuracy: 0.5, file: file, line: line)
        if needed > scroll.bounds.height + 0.5 {
            XCTAssertTrue(scroll.isScrollEnabled, "the actions scroll", file: file, line: line)
        }
        XCTAssertEqual(scroll.bounds.height, scene.menuFrame.height, accuracy: 0.5, file: file, line: line)
    }

    /// The constraints the menu's own views hold, to see that a size change doesn't add to them.
    func constraintCount(_ menu: PopMenuViewController) -> Int {
        return menu.view.constraints.count + menu.containerView.constraints.count + menu.backgroundView.constraints.count
    }

    func assertAtAnchor(_ scene: Scene, file: StaticString = #file, line: UInt = #line) {
        let menu = scene.menuFrame, anchor = scene.anchorFrame
        XCTAssertEqual(menu.minY, anchor.minY, accuracy: 0.5, "the menu opens level with its anchor", file: file, line: line)
        XCTAssertTrue(menu.maxX >= anchor.minX && menu.minX <= anchor.maxX, "the menu reaches over its anchor: menu \(menu), anchor \(anchor)", file: file, line: line)
        XCTAssertTrue(scene.menuViewFrame.contains(menu), "the menu is inside its view: \(menu)", file: file, line: line)
    }

    // MARK: Tests

    /// A wide window (the unfolded iPhone Duo is 669 pt): the menu opens at an anchor near its right
    /// edge, not clamped to some other screen's width.
    func testTheMenuOpensAtItsAnchorInAWideWindow() {
        let scene = Scene(size: CGSize(width: 669, height: 951))
        XCTAssertEqual(scene.menu.backgroundView.frame, scene.menu.view.bounds)
        assertAtAnchor(scene)
    }

    /// Resized while open (a fold, a rotation, an iPad window): the background still covers the
    /// whole view, the menu follows its anchor, and nothing is added each time.
    func testResizingWhileOpenKeepsTheBackgroundTheMenuAndTheConstraints() {
        let scene = Scene(size: CGSize(width: 467, height: 679))
        let constraints = constraintCount(scene.menu)
        for size in [CGSize(width: 669, height: 951), CGSize(width: 951, height: 669), CGSize(width: 467, height: 679), CGSize(width: 669, height: 951)] {
            scene.resize(to: size)
            XCTAssertEqual(scene.menu.backgroundView.frame, scene.menu.view.bounds, "after resizing to \(size)")
            assertAtAnchor(scene)
            XCTAssertEqual(constraintCount(scene.menu), constraints, "after resizing to \(size)")
        }
    }

    /// A blurred background is built once, not once more on every size change.
    func testABlurredBackgroundHasOneBlurAfterResizing() {
        let appearance = PopMenuAppearance()
        appearance.popMenuBackgroundStyle = .blurred(.dark)
        let scene = Scene(size: CGSize(width: 467, height: 679), appearance: appearance)
        scene.resize(to: CGSize(width: 669, height: 951))
        scene.resize(to: CGSize(width: 951, height: 669))
        let blurs = scene.menu.backgroundView.subviews.filter { $0 is UIVisualEffectView }
        XCTAssertEqual(blurs.count, 1)
        XCTAssertEqual(blurs.first?.frame, scene.menu.backgroundView.bounds)
    }

    /// Presented in a container that isn't at the window's origin: the menu still opens at its
    /// anchor, and its view fills the container.
    func testAnOffsetContainer() {
        let scene = Scene(size: CGSize(width: 669, height: 951), containerOffset: CGPoint(x: 0, y: 30))
        XCTAssertEqual(scene.menu.view.frame, scene.container.bounds)
        assertAtAnchor(scene)
        scene.resize(to: CGSize(width: 951, height: 669))
        assertAtAnchor(scene)
    }

    /// An anchor outside the safe area (a bar button in the column beside a camera housing): the menu
    /// still reaches over it, and stays inside the view.
    func testAnAnchorOutsideTheSafeArea() {
        let scene = Scene(size: CGSize(width: 466, height: 678), safeAreaRight: 80)
        XCTAssertTrue(scene.anchorFrame.minX > scene.menu.view.bounds.width - 80, "the anchor is in the inset")
        assertAtAnchor(scene)
        scene.resize(to: CGSize(width: 669, height: 951))
        assertAtAnchor(scene)
    }

    /// A container shorter than the menu: the menu fits inside it, and every action is reachable by
    /// scrolling, for a long menu and for a short one.
    func testAShortContainerKeepsEveryActionReachable() {
        for actions in [9, 4] {
            let scene = Scene(size: CGSize(width: 669, height: 160), actions: actions)
            let frame = scene.menuFrame
            XCTAssertTrue(scene.menuViewFrame.contains(frame), "\(actions) actions fit: \(frame)")
            XCTAssertGreaterThan(frame.height, 0)
            assertEveryActionReachable(scene, actions: actions)
            XCTAssertTrue(actionsScroll(scene.menu)?.isScrollEnabled == true, "\(actions) actions scroll")
            // Back to a tall window: a short menu stops scrolling and fits its actions again.
            scene.resize(to: CGSize(width: 669, height: 951))
            assertEveryActionReachable(scene, actions: actions)
            XCTAssertEqual(actionsScroll(scene.menu)?.isScrollEnabled, actions >= 6, "\(actions) actions")
        }
    }

    /// The source view moves without the view changing size: the next layout follows it.
    func testAMovedAnchorIsFollowedWithoutAResize() {
        let scene = Scene(size: CGSize(width: 669, height: 951))
        assertAtAnchor(scene)
        scene.anchor.frame = CGRect(x: 300, y: 140, width: 44, height: 44)
        scene.menu.view.setNeedsLayout()
        scene.menu.view.layoutIfNeeded()
        assertAtAnchor(scene)
    }

    /// The safe area changes without the view changing size: the next layout keeps the menu inside it.
    func testASafeAreaChangeIsFollowedWithoutAResize() {
        let scene = Scene(size: CGSize(width: 669, height: 600), actions: 9)
        scene.menu.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 380, right: 0)
        scene.menu.view.setNeedsLayout()
        scene.menu.view.layoutIfNeeded()
        XCTAssertLessThanOrEqual(scene.menuFrame.maxY, 600 - 380 + 0.5, "inside the new safe area: \(scene.menuFrame)")
        assertEveryActionReachable(scene, actions: 9)
    }

    /// With no anchor and an uneven safe area, the menu is centred in the safe area and stays inside
    /// it, for a long menu and a short one, before and after the safe area changes.
    func testNoAnchorStaysInsideAnUnevenSafeArea() {
        for actions in [9, 4] {
            let scene = Scene(size: CGSize(width: 669, height: 600), anchored: false, actions: actions)
            for insets in [UIEdgeInsets(top: 40, left: 0, bottom: 414, right: 0), UIEdgeInsets(top: 300, left: 60, bottom: 20, right: 0)] {
                scene.menu.additionalSafeAreaInsets = insets
                scene.menu.view.setNeedsLayout()
                scene.menu.view.layoutIfNeeded()
                let b = scene.menu.view.bounds, i = scene.menu.view.safeAreaInsets
                let safe = CGRect(x: b.minX + i.left, y: b.minY + i.top, width: b.width - i.left - i.right, height: b.height - i.top - i.bottom)
                let frame = scene.menuFrame
                XCTAssertGreaterThanOrEqual(frame.minY, safe.minY - 0.5, "\(actions) actions, \(insets): \(frame)")
                XCTAssertLessThanOrEqual(frame.maxY, safe.maxY + 0.5, "\(actions) actions, \(insets): \(frame)")
                XCTAssertEqual(frame.midX, safe.midX, accuracy: 0.5, "centred across the safe area")
                assertEveryActionReachable(scene, actions: actions)
            }
        }
    }

    /// With no anchor the menu is centred in its view, before and after a resize.
    func testNoAnchorCentresTheMenu() {
        let scene = Scene(size: CGSize(width: 669, height: 951), anchored: false)
        XCTAssertEqual(scene.menuFrame.midX, scene.menuViewFrame.midX, accuracy: 0.5)
        XCTAssertEqual(scene.menuFrame.midY, scene.menuViewFrame.midY, accuracy: 0.5)
        scene.resize(to: CGSize(width: 951, height: 669))
        XCTAssertEqual(scene.menuFrame.midX, scene.menuViewFrame.midX, accuracy: 0.5)
        XCTAssertEqual(scene.menuFrame.midY, scene.menuViewFrame.midY, accuracy: 0.5)
    }

    /// Enough actions to scroll, in a short window: the menu fits inside the view, under its anchor.
    func testAScrollingMenuInAShortWindow() {
        let scene = Scene(size: CGSize(width: 951, height: 669), actions: 9)
        XCTAssertTrue(actionsScroll(scene.menu)?.isScrollEnabled == true, "scrolls")
        assertAtAnchor(scene)
        scene.resize(to: CGSize(width: 669, height: 400))
        XCTAssertTrue(scene.menuViewFrame.contains(scene.menuFrame), "fits after the resize: \(scene.menuFrame)")
        XCTAssertEqual(scene.menu.backgroundView.frame, scene.menu.view.bounds)
    }
}
