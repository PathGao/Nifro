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
