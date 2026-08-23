import SwiftUI
import Combine
import IOKit.ps


final class PowerSourceWatcher {
	enum PowerSource {
		case internalBattery
		case externalUnlimited
		case externalUPS

		var isUsingBattery: Bool { self == .internalBattery }

		fileprivate init(identifier: String) {
			switch identifier {
			case kIOPMBatteryPowerKey:
				self = .internalBattery
			case kIOPMACPowerKey:
				self = .externalUnlimited
			case kIOPMUPSPowerKey:
				self = .externalUPS
			default:
				self = .externalUnlimited

				assertionFailure("This should not happen as `IOPSGetProvidingPowerSourceType` is documented to return one of the defined types")
			}
		}
	}

	private lazy var didChangeSubject = CurrentValueSubject<PowerSource, Never>(powerSource)

	/**
	Publishes the power source when it changes. It also publishes an initial event.
	*/
	private(set) lazy var didChangePublisher = didChangeSubject.eraseToAnyPublisher()

	var powerSource: PowerSource {
		let identifier = IOPSGetProvidingPowerSourceType(nil)!.takeRetainedValue() as String
		return PowerSource(identifier: identifier)
	}

	init?() {
		let powerSourceCallback: IOPowerSourceCallbackType = { context in
			// Force-unwrapping is safe here as we're the ones passing the `context`.
			let this = Unmanaged<PowerSourceWatcher>.fromOpaque(context!).takeUnretainedValue()
			this.internalOnChange()
		}

		guard
			let runLoopSource = IOPSCreateLimitedPowerNotification(powerSourceCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))?.takeRetainedValue()
		else {
			return nil
		}

		CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
	}

	private func internalOnChange() {
		didChangeSubject.send(powerSource)
	}
}


enum SSEvents {
	/**
	Publishes when the machine wakes from sleep.
	*/
	static var deviceDidWake: some Publisher<Void, Never> {
		NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
			.map { _ in }
	}

	/**
	Publishes when the configuration of the displays attached to the computer is changed.

	The configuration change can be made either programmatically or when the user changes settings in the Displays control panel.
	*/
	static var screenParametersDidChange: some Publisher<Void, Never> {
		NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
			.map { _ in }
	}

	/**
	Publishes when the screen becomes locked/unlocked.
	*/
	static var isScreenLocked: some Publisher<Bool, Never> {
		Publishers.Merge(
			DistributedNotificationCenter.default().publisher(for: .screenIsLocked).map { _ in true },
			DistributedNotificationCenter.default().publisher(for: .screenIsUnlocked).map { _ in false }
		)
	}
}


extension SSEvents {
	private struct AppOpenURLPublisher: Publisher {
		// We need this abstraction as `kAEGetURL` can only be subscribed to once.
		private final class EventManager {
			typealias Handler = (URLComponents) -> Void

			nonisolated(unsafe) static let shared = EventManager()

			private init() {}

			private var handlers = [UUID: Handler]()

			// Installed with `NSAppleEventManager.setEventHandler`, which takes a selector. Nothing references it by name.
			@objc
			private func handleEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
				guard
					let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
					let urlComponents = URLComponents(string: urlString)
				else {
					return
				}

				for handler in handlers.values {
					handler(urlComponents)
				}
			}


			func add(_ handler: @escaping Handler) -> UUID {
				if handlers.isEmpty {
					NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
				}

				let id = UUID()
				handlers[id] = handler
				return id
			}

			func remove(_ id: UUID) {
				handlers[id] = nil

				if handlers.isEmpty {
					NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
				}
			}
		}

		private final class InternalSubscription<S: Subscriber>: Subscription where S.Input == Output, S.Failure == Failure {
			private var id: UUID?

			var subscriber: S?

			init() {
				self.id = EventManager.shared.add { [weak self] in
					_ = self?.subscriber?.receive($0)
				}
			}

			deinit {
				if let id {
					EventManager.shared.remove(id)
				}
			}

			func request(_ demand: Subscribers.Demand) {}

			func cancel() {
				subscriber = nil
			}
		}

		typealias Output = URLComponents
		typealias Failure = Never

		func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
			let subscription = InternalSubscription<S>()
			subscription.subscriber = subscriber
			subscriber.receive(subscription: subscription)
		}
	}

	/**
	Publishes when the app receives an open URL event.

	This can be useful for implementing support for a custom URL scheme.

	If you use SwiftUI, you should use `View#onOpenURL` instead.

	It returns `URLComponents` as it's more convenient, and also, `URL` does not support `foo:action` type URLs (without the slashes).

	- Important: You must set up the listener before the app finishes launching. Ideally, in the app controller's initializer.
	*/
	nonisolated(unsafe) static let appOpenURL: some Publisher<URLComponents, Never> = AppOpenURLPublisher()
}
