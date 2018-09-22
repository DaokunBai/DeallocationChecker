import UIKit

@objc
public class DeallocationCheckerManager: NSObject {

    public enum LeakedState {
        case leaked
        case notLeaked
    }

    public typealias Callback = (LeakedState, UIViewController.Type) -> ()

    public enum Handler {
        // Leads to preconditionFailure being called when a view controller didn't deallocate.
        case precondition
        case callback(Callback)
    }

    @objc
    public static let shared = DeallocationCheckerManager()

    private(set) var handler: Handler?

    /// Sets up the handler then used in all `checkDeallocation*` methods.
    /// It is recommended to use DeallocationChecker only in the DEBUG configuration by wrapping this call inside
    /// ```
    /// #if DEBUG
    ///     DeallocationCheckerManager.shared.setup(with: .precondition)
    /// #endif
    /// ```
    /// call.
    ///
    /// This method isn't exposed to Obj-C because we use an enumeration that isn't compatible with Obj-C.
    public func setup(with handler: Handler) {
        self.handler = handler
    }

    /// This method asserts whether a view controller gets deallocated after it disappeared
    /// due to one of these reasons:
    /// - it was removed from its parent, or
    /// - it (or one of its parents) was dismissed.
    ///
    /// The method calls the `handler` if it's non-nil.
    ///
    /// **You should call this method only from UIViewController.viewDidDisappear(_:).**
    /// - Parameter delay: Delay after which the check if a
    ///                    view controller got deallocated is performed
    @objc(checkDeallocationOf:afterDelay:)
    public func checkDeallocation(of viewController: UIViewController, afterDelay delay: TimeInterval = 2.0) {
        guard let handler = DeallocationCheckerManager.shared.handler else {
            return
        }

        let rootParentViewController = viewController.dch_rootParentViewController

        // `UITabBarController` keeps a strong reference to view controllers that disappeared from screen. So, we don't have to check if they've been deallocated.
        guard !rootParentViewController.isKind(of: UITabBarController.self) else {
            return
        }

        // We don't check `isBeingDismissed` simply on this view controller because it's common
        // to wrap a view controller in another view controller (e.g. a stock UINavigationController)
        // and present the wrapping view controller instead.
        if viewController.isMovingFromParent || rootParentViewController.isBeingDismissed {
            let viewControllerType = type(of: viewController)
            let disappearanceSource: String = viewController.isMovingFromParent ? "removed from its parent" : "dismissed"

            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: { [weak viewController] in
                let isLeaked = viewController != nil

                switch handler {
                case .precondition:
                    if isLeaked {
                        preconditionFailure("\(viewControllerType) not deallocated after being \(disappearanceSource)")
                    }
                case let .callback(callback):
                    callback(isLeaked ? .leaked : .notLeaked, viewControllerType)
                }
            })
        }
    }

    @objc(checkDeallocationWithDefaultDelayOf:)
    public func checkDeallocationWithDefaultDelay(of viewController: UIViewController) {
        self.checkDeallocation(of: viewController)
    }

}

extension UIViewController {

    @available(*, deprecated, message: "Please switch to using methods on DeallocationCheckerManager. Also remember to call setup(with:) when your app starts.")
    @objc(dch_checkDeallocationAfterDelay:)
    public func dch_checkDeallocation(afterDelay delay: TimeInterval = 2.0) {
        DeallocationCheckerManager.shared.checkDeallocation(of: self, afterDelay: delay)
    }

    @available(*, deprecated, message: "Please switch to using methods on DeallocationCheckerManager. Also remember to call setup(with:) when your app starts.")
    @objc(dch_checkDeallocation)
    public func objc_dch_checkDeallocation() {
        DeallocationCheckerManager.shared.checkDeallocationWithDefaultDelay(of: self)
    }

    fileprivate var dch_rootParentViewController: UIViewController {
        var root = self

        while let parent = root.parent {
            root = parent
        }

        return root
    }
}
