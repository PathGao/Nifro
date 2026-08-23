@preconcurrency import WebKit
@preconcurrency import LinkPresentation
import SwiftUI
import Combine
import CryptoKit
import UniformTypeIdentifiers
import os
import Defaults

typealias Defaults = _Defaults
typealias Default = _Default
typealias AnyCancellable = Combine.AnyCancellable

// Extensions on system types, one MARK per type so the jump bar is usable.
// Anything with a name and a job of its own lives in its own file next door.

// MARK: - AnyCancellable
extension AnyCancellable {
	@MainActor private static var foreverStore = Set<AnyCancellable>()

	@MainActor
	func storeForever() {
		store(in: &Self.foreverStore)
	}
}
extension AnyCancellable {
	private enum AssociatedKeys {
		nonisolated(unsafe) static let cancellables = ObjectAssociation<Set<AnyCancellable>>(defaultValue: [])
	}

	/**
	Stores this AnyCancellable for the lifetime of the given `object`.
	*/
	func store(forTheLifetimeOf object: AnyObject) {
		store(in: &AssociatedKeys.cancellables[object])
	}
}

// MARK: - AssociationPolicy
enum AssociationPolicy {
	case assign
	case retainNonatomic
	case copyNonatomic
	case retain
	case copy

	var rawValue: objc_AssociationPolicy {
		switch self {
		case .assign:
			.OBJC_ASSOCIATION_ASSIGN
		case .retainNonatomic:
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		case .copyNonatomic:
			.OBJC_ASSOCIATION_COPY_NONATOMIC
		case .retain:
			.OBJC_ASSOCIATION_RETAIN
		case .copy:
			.OBJC_ASSOCIATION_COPY
		}
	}
}

// MARK: - AutofocusedTextField
final class AutofocusedTextField: NSTextField {
	override func viewDidMoveToWindow() {
		window?.makeFirstResponder(self)
	}
}

// MARK: - BidirectionalCollection
extension BidirectionalCollection where Element: Equatable {
	/**
	Get the element before the first element equaling the given element, or the last element if there's no element before or if the given element is `nil`

	This can be useful when imitating a circular array.
	*/
	func elementBeforeOrLast(_ element: Element?) -> Element? {
		guard
			let element,
			let previousElement = self.element(before: element)
		else {
			return last
		}

		return previousElement
	}
}

// MARK: - Binding
extension Binding {
	/**
	Convert a binding with an optional value to a binding with a non-optional value by using the given default value if the binding value is `nil`.

	```
	struct ContentView: View {
		private static let defaultInterval = 60.0

		private var interval: Binding<Double> {
			$optionalInterval.withDefaultValue(Self.defaultInterval)
		}

		var body: some View {}
	}
	```
	*/
	func withDefaultValue<T>(_ defaultValue: T) -> Binding<T> where Value == T? {
		.init(
			get: { wrappedValue ?? defaultValue },
			set: {
				wrappedValue = $0
			}
		)
	}
}
extension Binding {
	/**
	Convert a binding with an optional value to a binding with a boolean value representing whether the original binding value is not `nil`.

	- Parameter trueSetValue: The value used when the binding value is set to `true`.

	```
	struct ContentView: View {
		private static let defaultInterval = 60.0

		private var hasInterval: Binding<Bool> {
			$optionalInterval.isNotNil(trueSetValue: Self.defaultInterval)
		}

		var body: some View {}
	}
	```
	*/
	func isNotNil<T>(trueSetValue: T) -> Binding<Bool> where Value == T? {
		.init(
			get: { wrappedValue != nil },
			set: {
				wrappedValue = $0 ? trueSetValue : nil
			}
		)
	}
}
extension Binding {
	/**
	Listen to `didSet` of a Binding.
	*/
	func didSet(_ didSet: @escaping ((newValue: Value, oldValue: Value)) -> Void) -> Self {
		.init(
			get: { wrappedValue },
			set: { newValue in
				let oldValue = wrappedValue
				wrappedValue = newValue
				didSet((newValue, oldValue))
			}
		)
	}
}
extension Binding<Double> {
	// TODO: Maybe make a general `Binding#convert()` function that accepts a converter. Something like `binding.convert(.secondsToMinutes)`?
	var secondsToMinutes: Self {
		map(
			get: { $0 / 60 },
			set: { $0 * 60 }
		)
	}
}
extension Binding {
	/**
	Transform a binding.

	You can even change the type of the binding.

	```
	$foo.map(
		get: { $0.uppercased() },
		set: { $0.lowercased() }
	)
	```
	*/
	func map<Result>(
		get: @escaping (Value) -> Result,
		set: @escaping (Result) -> Value
	) -> Binding<Result> {
		.init(
			get: { get(wrappedValue) },
			set: { newValue in
				wrappedValue = set(newValue)
			}
		)
	}


	/**
	Transform the value on `get`.

	- Important: If you want to simply map using a property, you can just do `$foo.someProperty` instead, thanks to dynamic member support in `Binding`.

	```
	$foo.getMap { $0.uppercased() }
	```
	*/
	func getMap(
		_ get: @escaping (Value) -> Value
	) -> Self {
		.init(
			get: { get(wrappedValue) },
			set: { newValue in
				wrappedValue = newValue
			}
		)
	}
}
// MARK: - BindingCollection
extension BindingCollection where Base.Element: Identifiable {
	/**
	Get the element with the given `ID` in a collection of `Identifible` elements.

	It assumes there are no duplicates and it will just get the first matching element.
	*/
	subscript(id id: Base.Element.ID) -> Binding<Base.Element>? {
		first { $0.wrappedValue.id == id }
	}
}

// MARK: - CFUUID
extension CFUUID {
	var toUUID: UUID {
		let bytes = CFUUIDGetUUIDBytes(self)

		let newBytes = (
			bytes.byte0,
			bytes.byte1,
			bytes.byte2,
			bytes.byte3,
			bytes.byte4,
			bytes.byte5,
			bytes.byte6,
			bytes.byte7,
			bytes.byte8,
			bytes.byte9,
			bytes.byte10,
			bytes.byte11,
			bytes.byte12,
			bytes.byte13,
			bytes.byte14,
			bytes.byte15
		)

		return .init(uuid: newBytes)
	}
}

// MARK: - CGSize
extension CGSize {
	/**
	Create a CGSize from string dimensions in the format `100x100`.
	*/
	static func from(dimensions: String) -> Self? {
		let parts = dimensions.split(separator: "x").compactMap { Int($0) }

		guard parts.count == 2 else {
			return nil
		}

		return self.init(width: parts[0], height: parts[1])
	}
}

// MARK: - CharacterSet
extension CharacterSet {
	/**
	Characters allowed to be unescaped in an URL.

	https://tools.ietf.org/html/rfc3986#section-2.3
	*/
	static let urlUnreservedRFC3986 = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

// MARK: - CocoaButton
struct CocoaButton: NSViewRepresentable {
	typealias NSViewType = NSButton

	enum KeyEquivalent: String {
		case escape = "\u{1b}"
		case `return` = "\r"
	}

	var title: String?
	var attributedTitle: NSAttributedString?
	let keyEquivalent: KeyEquivalent?
	let bezelStyle: NSButton.BezelStyle
	let action: () -> Void

	init(
		_ title: String,
		keyEquivalent: KeyEquivalent? = nil,
		bezelStyle: NSButton.BezelStyle = .rounded,
		action: @escaping () -> Void
	) {
		self.title = title
		self.keyEquivalent = keyEquivalent
		self.bezelStyle = bezelStyle
		self.action = action
	}


	func makeNSView(context: Context) -> NSViewType {
		let nsView = NSButton(title: "", target: nil, action: nil)
		nsView.wantsLayer = true
		nsView.translatesAutoresizingMaskIntoConstraints = false
		nsView.setContentHuggingPriority(.defaultHigh, for: .vertical)
		nsView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		return nsView
	}

	func updateNSView(_ nsView: NSViewType, context: Context) {
		if attributedTitle == nil {
			nsView.title = title ?? ""
		}

		if title == nil {
			nsView.attributedTitle = attributedTitle ?? "".toNSAttributedString
		}

		nsView.keyEquivalent = keyEquivalent?.rawValue ?? ""
		nsView.bezelStyle = bezelStyle

		nsView.onAction = { _ in
			action()
		}
	}
}

// MARK: - Collection
extension Collection {
	/**
	Works on strings too, since they're just collections.
	*/
	var nilIfEmpty: Self? { isEmpty ? nil : self }
}
extension Collection {
	/**
	Returns a infinite sequence with unique random elements from the collection.

	Elements will only repeat after all elements have been seen.

	This can be useful for slideshows and music playlists where you want to ensure that the elements are better spread out.

	If the collection only has a single element, that element will be repeated forever.
	If the collection is empty, it will never return any elements.

	```
	let sequence = [1, 2, 3, 4].infiniteUniformRandomSequence()

	for element in sequence.prefix(3) {
		print(element)
	}
	//=> 3
	//=> 1
	//=> 2

	let iterator = sequence.makeIterator()

	iterator.next()
	//=> 4
	iterator.next()
	//=> 1
	```
	*/
	func infiniteUniformRandomSequence() -> AnySequence<Element> {
		guard !isEmpty else {
			return [].eraseToAnySequence()
		}

		return AnySequence { () -> AnyIterator in
			guard count > 1 else {
				return AnyIterator { first }
			}

			var currentIndices = [Index]()
			var previousIndex: Index?

			return AnyIterator {
				if currentIndices.isEmpty {
					currentIndices = indices.shuffled()

					// Ensure there are no duplicate elements on the edges.
					if currentIndices.last == previousIndex {
						currentIndices = currentIndices.reversed()
					}
				}

				let index = currentIndices.popLast()! // It cannot be nil.
				previousIndex = index
				return self[index]
			}
		}
	}
}
extension Collection where Index == Int, Element: Equatable {
	/**
	Returns an array where the given element has moved to the `to` index.
	*/
	func moving(_ element: Element, to toIndex: Index) -> [Element] {
		var array = Array(self)
		array.move(element, to: toIndex)
		return array
	}
}
extension Collection where Index == Int, Element: Equatable {
	/**
	Returns an array where the given element has moved to the end of the array.
	*/
	func movingToEnd(_ element: Element) -> [Element] {
		moving(element, to: endIndex - 1)
	}
}
extension Collection where Element: Equatable {
}
extension Collection where Element: Identifiable {
	/**
	Returns an array where each element's ID in the collection equal to the given ID is modified.

	```
	struct Person: Identifiable {
		let id = UUID()
		var name: String
	}

	var people = [
		Person(name: "John"),
		Person(name: "Daniel"),
		Person(name: "John")
	]

	// …

	let personToRename = people[0]

	people = people.modifying(elementWithID: personToRename.id) {
		$0.name = "Johnny"
	}

	print(people)
	//=> [{name "Johnny"}, {name "Daniel"}, {name "Johnny"}]
	```
	*/
	func modifying(
		elementWithID id: Element.ID,
		update: (inout Element) throws -> Void
	) rethrows -> [Element] {
		try map { element in
			guard element.id == id else {
				return element
			}

			var copy = element
			try update(&copy)
			return copy
		}
	}
}
extension Collection {
	/**
	Returns an array where each element in the collection are modified.

	```
	people = people.modifying {
		$0.isCurrent = false
	}
	```
	*/
	func modifying(
		modify: (inout Element) throws -> Void
	) rethrows -> [Element] {
		try map {
			var copy = $0
			try modify(&copy)
			return copy
		}
	}
}
extension Collection where Element: Equatable {
	/**
	Get the element before the first element equaling the given element.

	```
	let x = [1, 2, 3]
	x.element(before: 2)
	//=> 1
	```
	*/
	func element(before element: Element) -> Element? {
		guard
			let elementIndex = firstIndex(of: element),
			let targetIndex = index(elementIndex, offsetBy: -1, limitedBy: startIndex)
		else {
			return nil
		}

		return self[targetIndex]
	}

	/**
	Get the element after the first element equaling the given element.

	```
	let x = [1, 2, 3]
	x.element(after: 2)
	//=> 3
	```
	*/
	func element(after element: Element) -> Element? {
		guard
			let elementIndex = firstIndex(of: element),
			let targetIndex = index(elementIndex, offsetBy: 1, limitedBy: index(endIndex, offsetBy: -1))
		else {
			return nil
		}

		return self[targetIndex]
	}
}
extension Collection where Element: Equatable {
	/**
	Get the element after the first element equaling the given element, or the first element if there's no element after or if the given element is `nil`

	This can be useful when imitating a circular array.
	*/
	func elementAfterOrFirst(_ element: Element?) -> Element? {
		guard
			let element,
			let nextElement = self.element(after: element)
		else {
			return first
		}

		return nextElement
	}
}
extension Collection where Element: Identifiable {
	/**
	Get the element with the given `ID` in a collection of `Identifible` elements.

	It assumes there are no duplicates and it will just get the first matching element.
	*/
	subscript(id id: Element.ID) -> Element? {
		first { $0.id == id }
	}
}

// MARK: - Data
extension Data {
	struct HexEncodingOptions: OptionSet {
		let rawValue: Int
		static let upperCase = Self(rawValue: 1 << 0)
	}

	func hexEncodedString(options: HexEncodingOptions = []) -> String {
		let hexDigits = options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef"
		let utf8Digits = Array(hexDigits.utf8)

		return String(unsafeUninitializedCapacity: count * 2) { pointer in
			var string = pointer.baseAddress!

			for byte in self {
				string[0] = utf8Digits[Int(byte / 16)]
				string[1] = utf8Digits[Int(byte % 16)]
				string += 2
			}

			return count * 2
		}
	}
}
extension Data {
	func sha256() -> Self {
		Data(SHA256.hash(data: self))
	}
}

// MARK: - DecodableDefault
enum DecodableDefault {}
extension DecodableDefault {
	@propertyWrapper
	struct Wrapper<Source: DecodableDefaultSource> {
		typealias Value = Source.Value
		var wrappedValue = Source.defaultValue
	}
}
extension DecodableDefault.Wrapper: Decodable {
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		wrappedValue = try container.decode(Value.self)
	}
}
extension DecodableDefault {
	typealias Source = DecodableDefaultSource
	typealias List = Decodable & ExpressibleByArrayLiteral
	typealias Map = Decodable & ExpressibleByDictionaryLiteral
	typealias Number = AdditiveArithmetic & Decodable

	enum Sources {
		enum True: Source {
			static let defaultValue = true
		}

		enum False: Source {
			static let defaultValue = false
		}

		enum EmptyString: Source {
			static let defaultValue = ""
		}

		enum EmptyList<T: List>: Source {
			static var defaultValue: T { [] }
		}

		enum EmptyMap<T: Map>: Source {
			static var defaultValue: T { [:] }
		}

		enum Zero<T: Number>: Source {
			static var defaultValue: T { .zero }
		}

		enum One: Source {
			static let defaultValue = 1
		}
	}
}
extension DecodableDefault {
	typealias True = Wrapper<Sources.True>
	typealias False = Wrapper<Sources.False>
	typealias EmptyString = Wrapper<Sources.EmptyString>
	typealias EmptyList<T: List> = Wrapper<Sources.EmptyList<T>>
	typealias EmptyMap<T: Map> = Wrapper<Sources.EmptyMap<T>>
	typealias Zero<T: Number> = Wrapper<Sources.Zero<T>>
	typealias One = Wrapper<Sources.One>

	typealias Custom = Wrapper // Just for readability.
}
extension DecodableDefault.Wrapper: Equatable where Value: Equatable {}
extension DecodableDefault.Wrapper: Hashable where Value: Hashable {}
extension DecodableDefault.Wrapper: Sendable where Value: Sendable {}
extension DecodableDefault.Wrapper: Identifiable where Value: Identifiable {
	var id: Value.ID { wrappedValue.id }
}
extension DecodableDefault.Wrapper: Encodable where Value: Encodable {
	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(wrappedValue)
	}
}

// MARK: - DecodableDefaultSource
protocol DecodableDefaultSource {
	associatedtype Value: Decodable
	static var defaultValue: Value { get }
}

// MARK: - Defaults
extension Defaults {
	/**
	Get a `Binding` for a `Defaults` key.
	*/
	static func binding<Value>(for key: Key<Value>) -> Binding<Value> {
		.init(
			get: { self[key] },
			set: {
				self[key] = $0
			}
		)
	}
}
extension Defaults {
	/**
	Get a `BindingCollection` for a `Defaults` key.
	*/
	static func bindingCollection<Value>(for key: Key<Value>) -> BindingCollection<Value> where Value: MutableCollection & RandomAccessCollection {
		.init(base: binding(for: key))
	}
}

// MARK: - Dictionary
extension Dictionary {
	func compactValues<T>() -> [Key: T] where Value == T? {
		compactMapValues(\.self)
	}
}
extension Dictionary where Key == String {
	/**
	This correctly escapes items. See `escapeQueryComponent`.
	*/
	var toQueryItems: [URLQueryItem] {
		map {
			URLQueryItem(
				name: escapeQueryComponent($0),
				value: escapeQueryComponent("\($1)")
			)
		}
	}

	var toQueryString: String {
		var components = URLComponents()
		components.queryItems = toQueryItems
		return components.query!
	}
}

// MARK: - Duration
extension Duration {
	var nanoseconds: Int64 {
		let (seconds, attoseconds) = components
		let secondsNanos = seconds * 1_000_000_000
		let attosecondsNanons = attoseconds / 1_000_000_000
		let (totalNanos, isOverflow) = secondsNanos.addingReportingOverflow(attosecondsNanons)
		return isOverflow ? .max : totalNanos
	}

	var toTimeInterval: TimeInterval { Double(nanoseconds) / 1_000_000_000 }
}

// MARK: - EmptyStateTextModifier
private struct EmptyStateTextModifier: ViewModifier {
	func body(content: Content) -> some View {
		content
			.font(.title2)
			.foregroundStyle(.tertiary)
	}
}

// MARK: - Error
extension Error {
	/**
	Present the error as an async sheet on the given window.

	The function resumes when the sheet is dismissed.

	- Note: This exists because the built-in `NSResponder#presentError(forModal:)` method requires too many arguments, selector as callback, and it says it's modal but it's not blocking, which is surprising.
	*/
	@MainActor
	func presentAsSheet(for window: NSWindow) async {
		await withCheckedContinuation { continuation in
			NSApp.presentErrorAsSheet(self, for: window) {
				continuation.resume()
			}
		}
	}


	/**
	Present the error as a blocking app-level modal dialog.

	Tread-safe.
	*/
	func presentAsModalLegacy() {
		DispatchQueue.main.async {
			SSApp.activateIfAccessory()
			NSApp.presentError(self)
		}
	}

	/**
	Present the error as a blocking app-level modal dialog.
	*/
	@MainActor
	func presentAsModal() {
		// It seems this is not yet working correctly: https://github.com/feedback-assistant/reports/issues/288
//		SSApp.activateIfAccessory()
//		NSApp.presentError(self)

		presentAsModalLegacy()
	}

	/**
	Present the error as an async sheet on the given window if the window is not `nil`, otherwise as an app-modal dialog.

	The function resumes when the dialog is dismissed.
	*/
	@MainActor
	func present(in window: NSWindow? = nil) async {
		guard let window else {
			presentAsModal()
			return
		}

		await presentAsSheet(for: window)
	}
}
extension Error {
	// Check if the error is a WKWebView `Plug-in handled load` error, which can happen when you open a video directly. It's more like a notification and it can be safely ignored.
	var isWebViewPluginHandledLoad: Bool {
		let nsError = self as NSError
		return nsError.domain == "WebKitErrorDomain" && nsError.code == 204
	}
}
extension Error {
	public var isCancelled: Bool {
		do {
			throw self
		} catch is CancellationError, URLError.cancelled, CocoaError.userCancelled {
			return true
		} catch {
			return false
		}
	}
}

// MARK: - Font

// MARK: - InfoPopoverButton
extension InfoPopoverButton<Text> {
	init(_ text: some StringProtocol, maxWidth: Double = 240) {
		self.content = Text(text)
		self.maxWidth = maxWidth
	}
}

// MARK: - KeyedDecodingContainer

// MARK: - LPLinkMetadata
extension LPLinkMetadata: @retroactive @unchecked Sendable {}

// MARK: - LPMetadataProvider
extension LPMetadataProvider: @retroactive @unchecked Sendable {}

// MARK: - NSAlert
extension NSAlert {
	/**
	Show an async alert sheet on a window.
	*/
	@discardableResult
	static func show(
		in window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil
	) async -> NSApplication.ModalResponse {
		let alert = NSAlert(
			title: title,
			message: message,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex
		)

		guard let window else {
			return await alert.run()
		}

		return await alert.beginSheetModal(for: window)
	}

	/**
	Show an alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title,
			message: message,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex
		)
		.runModal(for: window)
	}

	/**
	The index in the `buttonTitles` array for the button to use as default.

	Set `-1` to not have any default. Useful for really destructive actions.
	*/
	var defaultButtonIndex: Int {
		get {
			buttons.firstIndex { $0.keyEquivalent == "\r" } ?? -1
		}
		set {
			// Clear the default button indicator from other buttons.
			for button in buttons where button.keyEquivalent == "\r" {
				button.keyEquivalent = ""
			}

			if newValue != -1 {
				buttons[newValue].keyEquivalent = "\r"
			}
		}
	}

	convenience init(
		title: String,
		message: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style

		if let message {
			self.informativeText = message
		}

		addButtons(withTitles: buttonTitles)

		if let defaultButtonIndex {
			self.defaultButtonIndex = defaultButtonIndex
		}
	}

	/**
	Runs the alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window else {
			return runModal()
		}

		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}

	/**
	Adds buttons with the given titles to the alert.
	*/
	func addButtons(withTitles buttonTitles: [String]) {
		for buttonTitle in buttonTitles {
			addButton(withTitle: buttonTitle)
		}
	}
}
extension NSAlert {
	/**
	Workaround to allow using `NSAlert` in a `Task`.

	[FB9857161](https://github.com/feedback-assistant/reports/issues/288)
	*/
	@discardableResult
	func run() async -> NSApplication.ModalResponse {
		await withCheckedContinuation { continuation in
			DispatchQueue.main.async { [self] in
				continuation.resume(returning: runModal())
			}
		}
	}
}

// MARK: - NSControl
extension NSControl: ControlActionClosureProtocol {}

// MARK: - NSError
extension NSError {
	/**
	Use this for generic app errors.

	- Note: Prefer using a specific enum-type error whenever possible.

	- Parameter description: The description of the error. This is shown as the first line in error dialogs.
	- Parameter recoverySuggestion: Explain how the user how they can recover from the error. For example, "Try choosing a different directory". This is usually shown as the second line in error dialogs.
	- Parameter userInfo: Metadata to add to the error. Can be a custom key or any of the `NSLocalizedDescriptionKey` keys except `NSLocalizedDescriptionKey` and `NSLocalizedRecoverySuggestionErrorKey`.
	- Parameter domainPostfix: String to append to the `domain` to make it easier to identify the error. The domain is the app's bundle identifier.
	*/
	static func appError(
		_ description: String,
		recoverySuggestion: String? = nil,
		userInfo: [String: Any] = [:],
		domainPostfix: String? = nil
	) -> Self {
		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = description

		if let recoverySuggestion {
			userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
		}

		return .init(
			domain: domainPostfix.map { "\(SSApp.idString) - \($0)" } ?? SSApp.idString,
			code: 1, // This is what Swift errors end up as.
			userInfo: userInfo
		)
	}
}

// MARK: - NSEvent
extension NSEvent {
	static var modifiers: ModifierFlags {
		modifierFlags
			.intersection(.deviceIndependentFlagsMask)
			// We remove `capsLock` as it shouldn't affect the modifiers.
			// We remove `numericPad`/`function` as arrow keys trigger it, use `event.specialKeys` instead.
			.subtracting([.capsLock, .numericPad, .function])
	}
}

// MARK: - NSGestureRecognizer
extension NSGestureRecognizer: ControlActionClosureProtocol {}

// MARK: - NSImage
// TODO: Check if any of these can be removed when targeting macOS 15.
extension NSImage: @retroactive @unchecked Sendable {}

// MARK: - NSItemProvider
extension NSItemProvider: @retroactive @unchecked Sendable {}
extension NSItemProvider {
	/**
	Carries a value across a continuation boundary.

	`loadObject` produces its result on an arbitrary queue and never touches it again, so the value is handed over rather than shared. The compiler cannot see that, hence the unchecked conformance.
	*/
	private struct Transfer<Value>: @unchecked Sendable {
		let value: Value
	}

	func loadObject<T>(ofClass: T.Type) async throws -> T? where T: NSItemProviderReading {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Transfer<T?>, Error>) in
			_ = loadObject(ofClass: ofClass) { data, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				continuation.resume(returning: Transfer(value: data as? T))
			}
		}
		.value
	}
}
extension NSItemProvider {
	func getImage() async -> NSImage? {
		try? await loadObject(ofClass: NSImage.self)
	}
}
// Strongly-typed versions of some of the methods.
extension NSItemProvider {
	func hasItemConforming(to contentType: UTType) -> Bool {
		hasItemConformingToTypeIdentifier(contentType.identifier)
	}
}

// MARK: - NSObjectProtocol
// MARK: - KVO utilities
extension NSObjectProtocol where Self: NSObject {
}

// MARK: - NSResponder
extension NSResponder {
	// This method is internally implemented on `NSResponder` as `Error` is generic which comes with many limitations.
	fileprivate func presentErrorAsSheet(
		_ error: Error,
		for window: NSWindow,
		didPresent: (() -> Void)?
	) {
		final class DelegateHandler {
			var didPresent: (() -> Void)?

			@objc
			func didPresentHandler() {
				didPresent?()
			}
		}

		let delegate = DelegateHandler()
		delegate.didPresent = didPresent

		presentError(
			error,
			modalFor: window,
			delegate: delegate,
			didPresent: #selector(delegate.didPresentHandler),
			contextInfo: nil
		)
	}
}

// MARK: - NSStatusBar
extension NSStatusBar {
}

// MARK: - NSToolbarItem
extension NSToolbarItem: ControlActionClosureProtocol {}

// MARK: - NSWindow
extension NSWindow.Level {
	private static func level(for cgLevelKey: CGWindowLevelKey) -> Self {
		.init(rawValue: Int(CGWindowLevelForKey(cgLevelKey)))
	}

	static let desktop = level(for: .desktopWindow)
	static let desktopIcon = level(for: .desktopIconWindow)
}

// MARK: - NSWorkspace
extension NSWorkspace {
	/**
	Bounces the Downloads folder in the Dock if present.

	Specify the URL to a file in the Downloads folder.
	*/
	func bounceDownloadsFolderInDock(for url: URL) {
		DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
	}
}

// MARK: - Notification
extension Notification.Name {
	/**
	Must be used with `DistributedNotificationCenter`.
	*/
	static let screenIsLocked = Self("com.apple.screenIsLocked")

	/**
	Must be used with `DistributedNotificationCenter`.
	*/
	static let screenIsUnlocked = Self("com.apple.screenIsUnlocked")
}

// MARK: - Numeric
extension Numeric {
}

// MARK: - ObjectAssociation
final class ObjectAssociation<Value: Any> {
	private let defaultValue: Value
	private let policy: AssociationPolicy

	init(defaultValue: Value, policy: AssociationPolicy = .retainNonatomic) {
		self.defaultValue = defaultValue
		self.policy = policy
	}

	subscript(index: AnyObject) -> Value {
		get {
			objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as? Value ?? defaultValue
		}
		set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, policy.rawValue)
		}
	}
}

// MARK: - OnDoubleClick
private struct OnDoubleClick<Content>: View where Content: View {
	let action: () -> Void
	let content: Content

	var body: some View {
		OnDoubleClickRepresentable(action: action, content: content)
	}
}

// MARK: - OnDoubleClickRepresentable
private struct OnDoubleClickRepresentable<Content: View>: NSViewRepresentable {
	final class HostingView<Content2: View>: NSHostingView<Content2> {
		var action: (() -> Void)?

		override func mouseDown(with event: NSEvent) {
			if event.clickCount == 2 {
				action?()
			}

			super.mouseDown(with: event)
		}
	}

	let action: () -> Void
	let content: Content

	func makeNSView(context: Context) -> HostingView<Content> {
		let nsView = HostingView(rootView: content)
		nsView.action = action
		return nsView
	}

	func updateNSView(_ nsView: HostingView<Content>, context: Context) {}
}

// MARK: - Publisher
// TODO: Remove when targeting macOS 15.
extension Publisher {
	/**
	Convert a publisher to a `Result`.
	*/
	func convertToResult() -> AnyPublisher<Result<Output, Failure>, Never> {
		map(Result.success)
			.catch { Just(.failure($0)) }
			.eraseToAnyPublisher()
	}
}

// MARK: - RangeReplaceableCollection
extension RangeReplaceableCollection {
	/**
	Move the element at the `from` index to the `to` index.
	*/
	mutating func move(from fromIndex: Index, to toIndex: Index) {
		guard fromIndex != toIndex else {
			return
		}

		insert(remove(at: fromIndex), at: toIndex)
	}
}
extension RangeReplaceableCollection where Element: Equatable {
	/**
	Move the first equal element to the `to` index.
	*/
	mutating func move(_ element: Element, to toIndex: Index) {
		guard let fromIndex = firstIndex(of: element) else {
			return
		}

		move(from: fromIndex, to: toIndex)
	}
}

// MARK: - Sequence
extension Sequence {
	/**
	Same as the above but supports returning optional values.

	```
	[(1, "a"), (nil, "b")].toDictionary { ($1, $0) }
	//=> ["a": 1, "b": nil]
	```
	*/
	func toDictionary<Key: Hashable, Value>(withKey pickKeyValue: (Element) -> (Key, Value?)) -> [Key: Value?] {
		var dictionary = [Key: Value?]()
		for element in self {
			let newElement = pickKeyValue(element)
			dictionary[newElement.0] = newElement.1
		}
		return dictionary
	}
}
extension Sequence {
	func eraseToAnySequence() -> AnySequence<Element> { .init(self) }
}
extension Sequence where Element: Equatable {
	/**
	Returns a new sequence without the elements in the sequence that equals the given element.

	```
	[1, 2, 1, 2].removing(2)
	//=> [1, 1]
	```
	*/
	func removingAll(_ element: Element) -> [Element] {
		filter { $0 != element }
	}
}
extension Sequence where Element: Equatable {
}

// MARK: - SetAlgebra
extension SetAlgebra {
	/**
	Insert the `value` if `shouldExist` is true, otherwise remove it.
	*/
	mutating func toggleExistence(_ value: Element, shouldExist: Bool) {
		if shouldExist {
			insert(value)
		} else {
			remove(value)
		}
	}
}

// MARK: - SimpleImageCacheKeyable
protocol SimpleImageCacheKeyable: Hashable {
	var cacheKey: String { get }
}

// MARK: - String
extension String {
	var toNSAttributedString: NSAttributedString { .init(string: self) }
}
extension String {
	var trimmed: Self {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}

	var trimmedTrailing: Self {
		replacing(/\s+$/, with: "")
	}

	func removingPrefix(_ prefix: Self) -> Self {
		guard hasPrefix(prefix) else {
			return self
		}

		return Self(dropFirst(prefix.count))
	}

	/**
	```
	"Unicorn".truncated(to: 4)
	//=> "Uni…"
	```
	*/
	func truncating(to number: Int, truncationIndicator: Self = "…") -> Self {
		if number <= 0 {
			return ""
		}

		if count > number {
			return Self(prefix(number - truncationIndicator.count)).trimmedTrailing + truncationIndicator
		}

		return self
	}
}
extension String {
	/**
	Make a URL more human-friendly by removing the scheme and `www.`.
	*/
	var removingSchemeAndWWWFromURL: Self {
		String(trimmingPrefix(/https?:\/\/(?:www\.)?/))
	}
}
extension String {
	/**
	```
	"foo bar".replacingPrefix("foo", with: "unicorn")
	//=> "unicorn bar"
	```
	*/
	func replacingPrefix(_ prefix: Self, with replacement: Self) -> Self {
		guard hasPrefix(prefix) else {
			return self
		}

		return replacement + dropFirst(prefix.count)
	}
}
extension String {
	/**
	Get the string as UTF-8 data.
	*/
	var toData: Data { Data(utf8) }
}
extension String {
	/**
	```
	"foo".sha256()
	//=> "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
	```
	*/
	func sha256() -> Self {
		toData.sha256().hexEncodedString()
	}
}
extension String: SimpleImageCacheKeyable {
	var cacheKey: String { self }
}

// MARK: - StringProtocol
extension StringProtocol {
	/**
	Check if the string only contains whitespace characters.
	*/
	var isWhitespace: Bool {
		allSatisfy(\.isWhitespace)
	}

	/**
	Check if the string is empty or only contains whitespace characters.
	*/
	var isEmptyOrWhitespace: Bool { isEmpty || isWhitespace }
}
extension StringProtocol {
	var nilIfEmptyOrWhitespace: Self? { isEmptyOrWhitespace ? nil : self }
}

// MARK: - Timer

// MARK: - URL
extension URL {
	/**
	Convenience for opening URLs.
	*/
	func open() {
		NSWorkspace.shared.open(self)
	}
}
extension URL: @retroactive ExpressibleByStringLiteral {
	/**
	Example:

	```
	let url: URL = "https://sindresorhus.com"
	```
	*/
	public init(stringLiteral value: StaticString) {
		self.init(string: "\(value)")!
	}
}
extension URL {
	func addingDictionaryAsQuery(_ dict: [String: String]) -> Self {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
		components.addDictionaryAsQuery(dict)
		return components.url ?? self
	}
}
extension URL {
	/**
	Check if a URL string is a valid URL.

	`URL(string:)` doesn't strictly validate the input. This one at least ensures there's a `scheme` and that the `host` has a TLD.
	*/
	static func isValid(string: String) -> Bool {
		guard let url = URL(string: string, encodingInvalidCharacters: false) else {
			return false
		}

		return url.isValid
	}

	/**
	Check if the `host` part of a URL is an IP address.
	*/
	var isHostAnIPAddress: Bool {
		guard let host else {
			return false
		}

		return Validators.isIP(host)
	}

	/**
	Check if `self` is a valid URL.

	`URL(string:)` doesn't strictly validate the input. This one at least ensures there's a `scheme` and that the `host` has a TLD.
	*/
	var isValid: Bool {
		guard
			!isFileURL,
			!isHostAnIPAddress
		else {
			return true
		}

		guard
			scheme != nil,
			let host
		else {
			return false
		}

		// Allow `localhost` and other local URLs without a domain.
		guard host.contains(".") else {
			return true
		}

		let hostComponents = host.components(separatedBy: ".")

		return hostComponents.count >= 2 &&
			!hostComponents[0].isEmpty &&
			hostComponents.last!.count > 1
	}
}
extension URL {
	/**
	`URLComponents` have better parsing than `URL` and supports things like `scheme:path` (notice the missing `//`).
	*/
	var components: URLComponents? {
		URLComponents(url: self, resolvingAgainstBaseURL: true)
	}
}
extension URL {
	var isLocal: Bool {
		guard let host = host?.nilIfEmpty?.lowercased() else {
			return false
		}

		return host == "localhost"
			|| host == "127.0.0.1"
			|| host == "::1"
	}
}
extension URL {
	/**
	Human-friendly representation of the URL: `https://sindresorhus.com/` → `sindresorhus.com`.
	*/
	var humanString: String {
		guard !isFileURL else {
			return tildePath
		}

		let string = normalized().absoluteString.removingSchemeAndWWWFromURL
		return string.removingPercentEncoding ?? string
	}
}
extension URL {
	/**
	Returns the user's real home directory when called in a sandboxed app.
	*/
	static let realHomeDirectory = Self(
		fileURLWithFileSystemRepresentation: getpwuid(getuid())!.pointee.pw_dir!,
		isDirectory: true,
		relativeTo: nil
	)

	/**
	Ensures the URL points to the closest directory if it's a file or self.
	*/
	var directoryURL: Self { hasDirectoryPath ? self : deletingLastPathComponent() }

	var tildePath: String {
		// Note: Can't use `FileManager.default.homeDirectoryForCurrentUser.relativePath` or `NSHomeDirectory()` here as they return the sandboxed home directory, not the real one.
		path.replacingPrefix(Self.realHomeDirectory.path, with: "~")
	}

	var exists: Bool { FileManager.default.fileExists(atPath: path) }
}
extension URL {
	/**
	Access a security-scoped resource.

	The access will be automatically relinquished at the end of the scope of the given `accessor`.

	- Important: Don't do anything async in the `accessor` as the resource access is only available synchronously in the `accessor` scope.
	*/
	func accessSecurityScopedResource<Value, E>(_ accessor: (URL) throws(E) -> Value) throws(E) -> Value {
		let didStartAccessing = startAccessingSecurityScopedResource()

		defer {
			if didStartAccessing {
				stopAccessingSecurityScopedResource()
			}
		}

		return try accessor(self)
	}
}
extension URL {
	/**
	Accepts a file URL to a directory or file. If it's a file, it will prompt for permissions to its containing directory.

	You have to manually call the returned method when you no longer need access to the URL.
	*/
	@MainActor
	func accessSandboxedURLByPromptingIfNeeded() -> (() -> Void) {
		SecurityScopedBookmarkManager.accessURLByPromptingIfNeeded(self)
	}
}
extension URL {
	/**
	Normalizes the URL to improve equality matching.

	- Note: It's currently very simple and lacks a lot of normalizations.

	```
	URL("https://sindresorhus.com/?").normalized()
	//=> "https://sindresorhus.com"
	```
	*/
	func normalized(
		removeFragment: Bool = false,
		removeQuery: Bool = false,
		removeDefaultPort: Bool = true,
		removeWWW: Bool = true
	) -> Self {
		let url = absoluteURL.standardized

		guard var components = url.components else {
			return self
		}

		if components.path == "/" {
			components.path = ""
		}

		// Remove port 80 if it's there as it's the default.
		if
			removeDefaultPort,
			components.port == 80
		{
			components.port = nil
		}

		// Lowercase host and scheme.
		components.host = components.host?.lowercased()
		components.scheme = components.scheme?.lowercased()

		if removeWWW {
			components.host = components.host?.removingPrefix("www.")
		}

		// Remove empty fragment.
		// - `https://sindresorhus.com/#`
		if components.fragment?.isEmpty == true {
			components.fragment = nil
		}

		// Remove empty query.
		// - `https://sindresorhus.com/?`
		if components.query?.isEmpty == true {
			components.query = nil
		}

		if removeFragment {
			components.fragment = nil
		}

		if removeQuery {
			components.query = nil
		}

		return components.url ?? self
	}
}
extension URL {
	enum PlaceholderError: LocalizedError {
		case failedToEncodePlaceholder(String)
		case invalidURLAfterSubstitution(String)

		var errorDescription: String? {
			switch self {
			case .failedToEncodePlaceholder(let placeholder):
				"Failed to encode placeholder “\(placeholder)”"
			case .invalidURLAfterSubstitution(let urlString):
				"New URL was not valid after substituting placeholders. URL string is “\(urlString)”"
			}
		}
	}

	/**
	Replaces any occurrences of `placeholder` in the URL with `replacement`.

	- Throws: An error if the placeholder could not be encoded or if the replacement would create an invalid URL.
	*/
	func replacingPlaceholder(_ placeholder: String, with replacement: String) throws -> URL {
		guard
			let encodedPlaceholder = placeholder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
		else {
			throw PlaceholderError.failedToEncodePlaceholder(placeholder)
		}

		let urlString = absoluteString.replacing(encodedPlaceholder, with: replacement)

		guard let newURL = URL(string: urlString, encodingInvalidCharacters: false) else {
			throw PlaceholderError.invalidURLAfterSubstitution(urlString)
		}

		return newURL
	}
}
// MARK: -


extension URL {
	/**
	Create a URL from a human string, gracefully.

	By default, it only accepts `localhost` as a TLD-less URL.

	```
	URL(humanString: "sindresorhus.com")?.absoluteString
	//=> "https://sindresorhus.com"
	```
	*/
	init?(humanString: String) {
		let string = humanString.trimmed

		guard
			!string.isEmpty,
			!string.hasPrefix("."),
			!string.hasSuffix("."),
			string != "https://",
			string != "http://",
			string != "file://"
		else {
			return nil
		}

		let isValid = string.contains(".")
			|| string.hasPrefix("localhost")
			|| string.hasPrefix("http://localhost")
			|| string.hasPrefix("https://localhost")
			|| string.hasPrefix("file://")

		guard
			!string.hasPrefix("https://"),
			!string.hasPrefix("http://"),
			!string.hasPrefix("file://")
		else {
			guard isValid else {
				return nil
			}

			self.init(string: string)
			return
		}

		guard isValid else {
			return nil
		}

		let url = string.replacing(/^(?!(?:\w+:)?\/\/)/, with: "https://")

		self.init(string: url)
	}
}
extension URL: SimpleImageCacheKeyable {
	var cacheKey: String { absoluteString }
}
extension URL {
	func incrementalFilename() -> Self {
		let pathExtension = pathExtension
		let filename = deletingPathExtension().lastPathComponent
		var url = self
		var counter = 0

		while FileManager.default.fileExists(atPath: url.path) {
			counter += 1
			url.deleteLastPathComponent()
			url.appendPathComponent("\(filename) (\(counter))", isDirectory: false)
			url.appendPathExtension(pathExtension)
		}

		return url
	}
}
extension URL {
	/**
	Whether the domain of the URL matches the given domain, with any or no subdomain.
	*/
	func hasDomain(_ domain: String) -> Bool {
		assert(!domain.hasPrefix("."))
		assert(domain.contains("."))

		guard let host else {
			return false
		}

		// `URL` does not have a way to get the domain without subdomains, so we fake it.
		return host == domain || host.hasSuffix(".\(domain)")
	}
}

// MARK: - URLComponents
extension URLComponents {
	mutating func addDictionaryAsQuery(_ dict: [String: String]) {
		percentEncodedQuery = dict.toQueryString
	}
}
extension URLComponents {
	/**
	This correctly escapes items. See `escapeQueryComponent`.
	*/
	var queryDictionary: [String: String] {
		get {
			queryItems?.toDictionary { ($0.name, $0.value) }.compactValues() ?? [:]
		}
		set {
			// Using `percentEncodedQueryItems` instead of `queryItems` since the query items are already custom-escaped. See `escapeQueryComponent`.
			percentEncodedQueryItems = newValue.toQueryItems
		}
	}
}

// MARK: - UUID
extension UUID: @retroactive Identifiable {
	public var id: Self { self }
}

// MARK: - Validators
enum Validators {
	static func isIPv4(_ string: String) -> Bool {
		IPv4Address(string) != nil
	}

	static func isIPv6(_ string: String) -> Bool {
		IPv6Address(string) != nil
	}

	static func isIP(_ string: String) -> Bool {
		isIPv4(string) || isIPv6(string)
	}
}

// MARK: - View
extension View {
	func multilineText() -> some View {
		lineLimit(nil)
			.fixedSize(horizontal: false, vertical: true)
	}
}
extension View {
	/**
	This overload makes it possible to preserve the type. For example, doing an `if` in a chain of `Text`-only modifiers.

	```
	Text("🦄")
		.if(isOn) {
			$0.fontWeight(.bold)
		}
		.kerning(10)
	```
	*/
	func `if`(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> Self
	) -> Self {
		condition() ? modify(self) : self
	}
}
extension View {
}
extension View {
	/**
	For empty states in the UI. For example, no items in a list, no search results, etc.
	*/
	func emptyStateTextStyle() -> some View {
		modifier(EmptyStateTextModifier())
	}
}
// Multiple `.alert` are stil broken in macOS 12.
extension View {
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: Text,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		background(
			EmptyView()
				.alert(
					title,
					isPresented: isPresented,
					actions: actions,
					message: message
				)
		)
	}

	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		alert2(
			Text(title),
			isPresented: isPresented,
			actions: actions,
			message: message
		)
	}


	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View
	) -> some View {
		alert2(
			title,
			isPresented: isPresented,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message {
					Text(message)
				}
			}
		)
	}


	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>
	) -> some View {
		alert2(
			title,
			message: message,
			isPresented: isPresented,
			actions: {} // swiftlint:disable:this trailing_closure
		)
	}
}
// Multiple `.confirmationDialog` are broken in macOS 12.
extension View {
	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: Text,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		background(
			EmptyView()
				.confirmationDialog(
					title,
					isPresented: isPresented,
					titleVisibility: titleVisibility,
					actions: actions,
					message: message
				)
		)
	}

	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: Text,
		message: String? = nil,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View
	) -> some View {
		confirmationDialog2(
			title,
			isPresented: isPresented,
			titleVisibility: titleVisibility,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message {
					Text(message)
				}
			}
		)
	}

	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View
	) -> some View {
		confirmationDialog2(
			Text(title),
			message: message,
			isPresented: isPresented,
			titleVisibility: titleVisibility,
			actions: actions
		)
	}
}
extension View {
	@ViewBuilder
	func ifLet<Value>(
		_ value: Value?,
		modifier: (Self, Value) -> some View
	) -> some View {
		if let value {
			modifier(self, value)
		} else {
			self
		}
	}
}
extension View {
}
extension View {
	/**
	Make the view subscribe to the given notification.
	*/
	func onNotification(
		_ name: Notification.Name,
		object: AnyObject? = nil,
		perform action: @escaping (Notification) -> Void
	) -> some View {
		onReceive(NotificationCenter.default.publisher(for: name, object: object), perform: action)
	}
}
extension View {
	/**
	Bind the native backing-window of a SwiftUI window to a property.
	*/
	func bindHostingWindow(_ window: Binding<NSWindow?>) -> some View {
		background(WindowAccessor(window))
	}
}
extension View {
	/**
	Access the native backing-window of a SwiftUI window.
	*/
	func accessHostingWindow(_ onWindow: @escaping (NSWindow?) -> Void) -> some View {
		modifier(WindowViewModifier(onWindow: onWindow))
	}

	/**
	Set the window level of a SwiftUI window.
	*/
	func windowLevel(_ level: NSWindow.Level) -> some View {
		accessHostingWindow {
			$0?.level = level
		}
	}
}
extension View {
	/**
	`.task()` with debouncing.
	*/
	func debouncingTask(
		id: some Equatable,
		priority: TaskPriority = .userInitiated,
		interval: Duration,
		@_inheritActorContext @_implicitSelfCapture _ action: @Sendable @escaping () async -> Void
	) -> some View {
		task(id: id, priority: priority) {
			do {
				try await Task.sleep(for: interval)
				await action()
			} catch {}
		}
	}
}
extension View {
}
extension View {
	/**
	Listen to double click events on the view.

	This exists as it's the only way to make double click not interfere with reordering a list.
	*/
	func onDoubleClick(
		_ action: @escaping () -> Void
	) -> some View {
		OnDoubleClick(action: action, content: self)
	}
}

// MARK: - WKPreferences
extension WKPreferences {
	// https://github.com/feedback-assistant/reports/issues/80
	var isDeveloperExtrasEnabled: Bool {
		get {
			value(forKey: "developerExtrasEnabled") as? Bool ?? false
		}
		set {
			setValue(newValue, forKey: "developerExtrasEnabled")
		}
	}
}

// MARK: - WKUserContentController
extension WKUserContentController {
	/**
	Add CSS to the page.
	*/
	func addCSS(_ css: String) {
		let source = WKWebView.createCSSInjectScript(css)

		let userScript = WKUserScript(
			source: source,
			injectionTime: .atDocumentStart,
			forMainFrameOnly: false,
			in: .defaultClient
		)

		addUserScript(userScript)
	}

	/**
	Add JavaScript to the page.

	You can use `await` at the top-level.

	The code runs in a separate realm from the website itself.
	*/
	func addJavaScript(_ javaScript: String) {
		let source =
			"""
			(async () => {
				\(javaScript)
			})();
			"""

		let userScript = WKUserScript(
			source: source,
			injectionTime: .atDocumentEnd,
			forMainFrameOnly: false,
			in: .world(name: UUID().uuidString)
		)

		addUserScript(userScript)
	}
}
extension WKUserContentController {
	private static let invertColorsCSS =
		"""
		:root {
			background-color: #fefefe;
			filter: invert(100%) hue-rotate(-180deg);
		}

		* {
			background-color: inherit;
		}

		img:not([src*='.svg']),
		body * [style*="background-image"],
		video,
		iframe {
			filter: invert(100%) hue-rotate(180deg) !important;
			background-color: unset !important;
		}
		"""

	/**
	Invert the colors on the page. Pseudo dark mode.
	*/
	func invertColors(onlyWhenInDarkMode: Bool) {
		if onlyWhenInDarkMode {
			addCSS(
				"""
				@media (prefers-color-scheme: dark) {
					\(Self.invertColorsCSS)
				}
				"""
			)
		} else {
			addCSS(Self.invertColorsCSS)
		}
	}
}
extension WKUserContentController {
	/**
	Keeps every audio and video element on the page at whatever the app last said, and keeps doing it
	as the page replaces them.

	Always injected, whatever the website's setting is, so that changing the setting is a message to
	a script that is already there rather than a reason to rebuild the page. Sound is the one setting
	most likely to be changed while looking at the thing it applies to, and rebuilding the page to
	apply it starts the video again from the beginning.

	It starts muted and waits to be told otherwise. Silence is the safe direction to be wrong in for
	the moment between the page starting and the app answering.
	*/
	private static let audioControlCode =
		"""
		(() => {
			const selector = 'audio, video';
			let muted = true;
			let rescanQueued = false;

			const adopt = element => {
				element.muted = muted;

				// A player that was only allowed to start because it was muted stays paused when the
				// mute comes off, and a wallpaper showing a paused video looks exactly like a
				// wallpaper showing a still. Starting it is part of turning the sound on.
				if (!muted && element.paused) {
					element.play().catch(() => {});
				}
			};

			const apply = () => {
				for (const element of document.querySelectorAll(selector)) {
					adopt(element);
				}
			};

			const rescan = () => {
				rescanQueued = false;
				apply();
			};

			// A full rescan is needed as well as muting on insertion: players reuse and reparent their
			// media elements, so a node that was muted on insertion can come back unmuted. But a live
			// stream's chat fires mutations continuously, and rescanning the document on every batch
			// made the cost scale with the chat rather than with the video. One rescan per frame is
			// enough, and it collapses a burst into a single pass.
			const observer = new MutationObserver(mutations => {
				for (const mutation of mutations) {
					for (const node of mutation.addedNodes) {
						if ('matches' in node && node.matches(selector)) {
							adopt(node);
						} else if ('querySelectorAll' in node) {
							for (const element of node.querySelectorAll(selector)) {
								adopt(element);
							}
						}
					}
				}

				if (!rescanQueued) {
					rescanQueued = true;
					requestAnimationFrame(rescan);
				}
			});

			// Watched in both states. Only watching while muted looks like a saving and is a bug: a
			// player inserts its media element well after the page has loaded, so with the sound on
			// the element arrives after the app has already spoken, finds nobody watching, and keeps
			// whatever the player set — which for a framed YouTube player is muted, because being
			// muted is the only way it was allowed to start. Turning the sound off and on again then
			// fixed it, because by then the element existed.
			const watch = () => {
				observer.observe(document, { childList: true, subtree: true });
			};

			const tellChildren = () => {
				for (let index = 0; index < window.frames.length; index++) {
					try {
						window.frames[index].postMessage({ \(audioMessageKey): muted }, '*');
					} catch (error) {}
				}
			};

			window.addEventListener('message', event => {
				const data = event.data;

				if (!data) {
					return;
				}

				if (typeof data.\(audioMessageKey) === 'boolean') {
					muted = data.\(audioMessageKey);
					apply();
					watch();
					tellChildren();
					return;
				}

				// Only the top frame is spoken to by the app, so only it knows the answer.
				if (data.\(audioAskKey) === true && window === window.top) {
					tellChildren();
				}
			});

			apply();
			watch();

			// A frame that loaded after the app last spoke never heard it. That is the normal case for
			// a framed video player: the page finishes, the app answers, and the player's frame arrives
			// afterwards and would sit muted with the sound turned on.
			if (window !== window.top) {
				try {
					window.top.postMessage({ \(audioAskKey): true }, '*');
				} catch (error) {}
			}
		})();
		"""

	// https://github.com/feedback-assistant/reports/issues/79
	/**
	Install the audio control. The setting itself is applied afterwards, and again on every load.
	*/
	func installAudioControl() {
		let userScript = WKUserScript(
			source: Self.audioControlCode,
			injectionTime: .atDocumentStart,
			forMainFrameOnly: false,
			in: .defaultClient
		)

		addUserScript(userScript)
	}
}

/**
The name on the message the audio script answers to. One definition, used by the script and by the
broadcast that reaches it.
*/
private let audioMessageKey = "__nifroAudioMuted"

/**
The name on the message a frame sends when it arrives too late to have heard the answer.
*/
private let audioAskKey = "__nifroAudioAsk"

extension WKWebView {
	/**
	Mute or unmute the page, now, without reloading it.

	Muting is done by holding every audio and video element muted rather than by silencing the web
	view, so it covers media elements and not sound a page generates with the Web Audio API.

	Said once, to the main frame. The script passes it down: the app cannot reach a subframe —
	`evaluateJavaScript` runs in the main frame only — and a video is very often not in the main
	frame, because a framed player puts it one frame down on another origin.
	*/
	func setAudioMuted(_ muted: Bool) {
		evaluateJavaScript(
			"window.postMessage({ \(audioMessageKey): \(muted) }, '*')",
			in: nil,
			in: .defaultClient
		)
	}
}
// MARK: - WKWebView
extension WKWebView {
	// Source: https://github.com/WebKit/webkit/blob/a77f5c97c5be3a392f626f444f2111a09a3520ca/Source/WebKit/UIProcess/API/Cocoa/WKMenuItemIdentifiers.mm
	/**
	Use this to modify the web view context menu in the `func willOpenMenu()` delegate method.

	```
	import WebKit

	final class SSWebView: WKWebView {
		private var excludedMenuItems: Set<MenuItemIdentifier> = [
			.toggleEnhancedFullScreen,
			.toggleFullScreen
		]

		override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
			menu.items.removeAll {
				guard let identifier = MenuItemIdentifier($0) else {
					return false
				}

				return excludedMenuItems.contains(identifier)
			}
		}
	}
	```
	*/
	enum MenuItemIdentifier: String {
		case copy = "WKMenuItemIdentifierCopy"
		case copyImage = "WKMenuItemIdentifierCopyImage"
		case copyLink = "WKMenuItemIdentifierCopyLink"
		case copyMediaLink = "WKMenuItemIdentifierCopyMediaLink"
		case downloadImage = "WKMenuItemIdentifierDownloadImage"
		case downloadLinkedFile = "WKMenuItemIdentifierDownloadLinkedFile"
		case downloadMedia = "WKMenuItemIdentifierDownloadMedia"
		case goBack = "WKMenuItemIdentifierGoBack"
		case goForward = "WKMenuItemIdentifierGoForward"
		case inspectElement = "WKMenuItemIdentifierInspectElement"
		case lookUp = "WKMenuItemIdentifierLookUp"
		case openFrameInNewWindow = "WKMenuItemIdentifierOpenFrameInNewWindow"
		case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
		case openLink = "WKMenuItemIdentifierOpenLink"
		case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
		case openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
		case paste = "WKMenuItemIdentifierPaste"
		case reload = "WKMenuItemIdentifierReload"
		case searchWeb = "WKMenuItemIdentifierSearchWeb"
		case showHideMediaControls = "WKMenuItemIdentifierShowHideMediaControls"
		case toggleEnhancedFullScreen = "WKMenuItemIdentifierToggleEnhancedFullScreen"
		case toggleFullScreen = "WKMenuItemIdentifierToggleFullScreen"
		case shareMenu = "WKMenuItemIdentifierShareMenu"
		case speechMenu = "WKMenuItemIdentifierSpeechMenu"

		init?(_ menuItem: NSMenuItem) {
			guard let rawIdentifier = menuItem.identifier?.rawValue else {
				return nil
			}

			self.init(rawValue: rawIdentifier)
		}
	}
}
extension WKWebView {
	/**
	A Safari user agent whose version number tracks the system instead of being frozen at build time.

	A hardcoded version goes stale. Sites that gate on it start showing "your browser is out of date" a year or two after release, which is what happened upstream (Plash#169, Google Calendar, four people, two years). Safari's marketing version has tracked the macOS major version since macOS 26, so deriving it from the running system costs nothing and keeps up.
	*/
	static let safariUserAgent: String = {
		let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
		return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).0 Safari/605.1.15"
	}()


	// https://github.com/feedback-assistant/reports/issues/81
	/**
	Whether the web view should have a background. Set to `false` to make it transparent.
	*/
	var drawsBackground: Bool {
		get {
			value(forKey: "drawsBackground") as? Bool ?? true
		}
		set {
			setValue(newValue, forKey: "drawsBackground")
		}
	}
}
extension WKWebView {
	nonisolated static func createCSSInjectScript(_ css: String) -> String {
		let textContent = css.addingPercentEncoding(withAllowedCharacters: .letters) ?? css

		// Injected at document start, so the style element gets appended to a document the page has not finished building. Frameworks that swap out `documentElement` or clear `head` on mount take our style with them, and the user's CSS stops applying. People report this as "my CSS works in Safari but not here" (Plash#173).
		//
		// Re-appending on mutation is the fix. The observer is cheap because it only watches childList on the root, and re-appending the same element is a move, not a duplicate.
		return
			"""
			(() => {
				const style = document.createElement('style');
				style.textContent = unescape('\(textContent)');
				style.dataset.nifroInjected = 'css';

				const attach = () => {
					const root = document.head ?? document.documentElement;

					if (root && style.parentNode !== root) {
						root.appendChild(style);
					}
				};

				attach();

				new MutationObserver(attach).observe(document, {
					childList: true,
					subtree: true
				});
			})();
			"""
	}
}
extension WKWebView {
	/**
	Centers a standalone image as WKWebView doesn't center it like Chrome and Firefox do.

	The image will aspect-fill the space available.
	*/
	func centerAndAspectFillImage(mimeType: String?) {
		guard mimeType?.hasPrefix("image/") == true else {
			return
		}

		let js = Self.createCSSInjectScript(
			"""
			/* Center image */
			body {
				display: flex;
				align-items: center;
				justify-content: center;
			}

			/* Aspect-fill image */
			img {
				width: 100%;
				height: 100%;
				object-fit: cover;
			}
			"""
		)

		evaluateJavaScript(js, in: nil, in: .defaultClient)
	}
}
extension WKWebsiteDataStore {
	/**
	Clear all website data like cookies, local storage, caches, etc.

	On the store rather than on a web view. It touches no web view and clears the shared store, so
	hanging it off one made callers reach for a web view they had no other use for.
	*/
	static func clearAllWebsiteData() async {
		HTTPCookieStorage.shared.removeCookies(since: .distantPast)

		let store = `default`()
		let types = allWebsiteDataTypes()
		let records = await store.dataRecords(ofTypes: types)
		await store.removeData(ofTypes: types, for: records)
	}
}
extension WKWebView {
	/**
	Returns `true` if the error can be ignored.
	*/
	static func canIgnoreError(_ error: Error) -> Bool {
		// Ignore the request being cancelled which can happen if the user clicks on a link while a website is loading.
		error.isCancelled || error.isWebViewPluginHandledLoad
	}
}

// MARK: - WebsiteIconFetcher
extension WebsiteIconFetcher: WKNavigationDelegate {
	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
		navigationResponse.isForMainFrame ? .allow : .cancel
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		continuation?.resume()
		continuation = nil // These delegate methods can be called multiple times.
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		continuation?.resume(throwing: error)
		continuation = nil
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		continuation?.resume(throwing: error)
		continuation = nil
	}
}

// MARK: - WindowAccessor
private struct WindowAccessor: NSViewRepresentable {
	private final class WindowAccessorView: NSView {
		@Binding var windowBinding: NSWindow?

		init(binding: Binding<NSWindow?>) {
			self._windowBinding = binding
			super.init(frame: .zero)
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			windowBinding = window
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError() // swiftlint:disable:this fatal_error_message
		}
	}

	@Binding var window: NSWindow?

	init(_ window: Binding<NSWindow?>) {
		self._window = window
	}

	func makeNSView(context: Context) -> NSView {
		WindowAccessorView(binding: $window)
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - WindowViewModifier
private struct WindowViewModifier: ViewModifier {
	@State private var window: NSWindow?

	let onWindow: (NSWindow?) -> Void

	func body(content: Content) -> some View {
		onWindow(window)

		return content
			.bindHostingWindow($window)
	}
}

// MARK: - Free functions
/**
Convenience function for initializing an object and modifying its properties.

```
let label = with(NSTextField()) {
	$0.stringValue = "Foo"
	$0.textColor = .systemBlue
	view.addSubview($0)
}
```
*/
@discardableResult
func with<T, E>(_ item: T, update: (inout T) throws(E) -> Void) throws(E) -> T {
	var this = item
	try update(&this)
	return this
}
func delay(_ duration: Duration, closure: @escaping () -> Void) {
	DispatchQueue.main.asyncAfter(deadline: .now() + duration.toTimeInterval, execute: closure)
}
func fatalError(
	because reason: FatalReason,
	function: StaticString = #function,
	file: StaticString = #fileID,
	line: Int = #line
) -> Never {
	fatalError("\(function): \(reason)", file: file, line: UInt(line))
}
/**
This should really not be necessary, but it's at least needed for my `formspree.io` form...

Otherwise is results in "Internal Server Error" after submitting the form

Relevant: https://www.djackson.org/why-we-do-not-use-urlcomponents/
*/
private func escapeQueryComponent(_ query: String) -> String {
	query.addingPercentEncoding(withAllowedCharacters: .urlUnreservedRFC3986)!
}
@MainActor
protocol ControlActionClosureProtocol: NSObjectProtocol {
	var target: AnyObject? { get set }
	var action: Selector? { get set }
}
/**
Default handlers for the UI for WKUIDelegate.

Test it with https://jsfiddle.net/sindresorhus/8moqrudL/

```
extension WebViewController: WKUIDelegate {
	func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
		webView.defaultAlertHandler(message: message)
	}

	func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
		webView.defaultConfirmHandler(message: message)
	}

	func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
		webView.defaultPromptHandler(prompt: prompt, defaultText: defaultText)
	}

	func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
		webView.defaultUploadPanelHandler(parameters: parameters)
	}

	func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
		webView.defaultAuthChallengeHandler(challenge: challenge)
	}
}
```
*/
extension WKWebView {
	/**
	Default handler for JavaScript `confirm()` to be used in `WKDelegate`.
	*/
	func defaultConfirmHandler(message: String) async -> Bool {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = message
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		return await alert.run() == .alertFirstButtonReturn
	}

	/**
	Default handler for JavaScript `prompt()` to be used in `WKDelegate`.
	*/
	func defaultPromptHandler(prompt: String, defaultText: String?) async -> String? {
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = prompt
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")

		let textField = AutofocusedTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
		textField.stringValue = defaultText ?? ""
		alert.accessoryView = textField

		return await alert.run() == .alertFirstButtonReturn ? textField.stringValue : nil
	}

	/**
	Default handler for JavaScript initiated upload panel to be used in `WKDelegate`.
	*/
	func defaultUploadPanelHandler(parameters: WKOpenPanelParameters) async -> [URL]? { // swiftlint:disable:this discouraged_optional_collection
		let openPanel = NSOpenPanel()
		openPanel.identifier = .init("WKWebView_defaultUploadPanelHandler")
		openPanel.level = .floating
		openPanel.prompt = "Choose"
		openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
		openPanel.canChooseFiles = !parameters.allowsDirectories
		openPanel.canChooseDirectories = parameters.allowsDirectories

		// It's intentionally modal as we don't want the user to interact with the website until they're done with the panel.
		return await openPanel.begin() == .OK ? openPanel.urls : nil
	}

	// Can be tested at https://jigsaw.w3.org/HTTP/Basic/ with `guest` as username and password.
	/**
	Default handler for websites requiring basic authentication. To be used in `WKDelegate`.
	*/
	func defaultAuthChallengeHandler(
		challenge: URLAuthenticationChallenge,
		allowSelfSignedCertificate: Bool = false
	) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
		guard
			let url,
			let host = url.host
		else {
			return (.performDefaultHandling, nil)
		}

		guard
			challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic
				|| challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest
		else {
			guard
				allowSelfSignedCertificate || url.isLocal,
				let serverTrust = challenge.protectionSpace.serverTrust
			else {
				return (.performDefaultHandling, nil)
			}

			let exceptions = SecTrustCopyExceptions(serverTrust)

			guard SecTrustSetExceptions(serverTrust, exceptions) else {
				return (.cancelAuthenticationChallenge, nil)
			}

			return (.useCredential, .init(trust: serverTrust))
		}

		let alert = NSAlert()
		alert.messageText = "Log in to \(host)"
		alert.addButton(withTitle: String(localized: "Log In"))
		alert.addButton(withTitle: "Cancel")

		let view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 54))
		alert.accessoryView = view

		let username = AutofocusedTextField(frame: CGRect(x: 0, y: 32, width: 200, height: 22))
		username.contentType = .username
		username.placeholderString = String(localized: "Username")
		view.addSubview(username)

		let password = NSSecureTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 22))
		password.contentType = .password
		password.placeholderString = String(localized: "Password")
		view.addSubview(password)

		// TODO: It doesn't continue tabbing to the buttons after the password field.
		username.nextKeyView = password

		SSApp.activateIfAccessory()

		guard await alert.run() == .alertFirstButtonReturn else {
			return (.rejectProtectionSpace, nil)
		}

		let credential = URLCredential(
			user: username.stringValue,
			password: password.stringValue,
			persistence: .synchronizable
		)

		return (.useCredential, credential)
	}
}
/**
Wrap a value in an `ObservableObject` where the given `Publisher` triggers it to update. Note that the value is static and must be accessed as `.wrappedValue`. The publisher part is only meant to trigger an observable update.

- Important: If you pass a value type, it will obviously not be kept in sync with the source.

```
struct ContentView: View {
	@StateObject private var foo = ObservableValue(
		value: someNonReactiveValue,
		publisher: Foo.publisher
	)

	var body: some View {}
}
```

You can even pass in a meta type (`Foo.self`), for example, to wrap an struct:

```
struct Display {
	static var text: String { … }

	@MainActor static let observable = ObservableValue(
		value: Self.self,
		publisher: NotificationCenter.default
			.publisher(for: NSApplication.didChangeScreenParametersNotification)
	)
}

// …

struct ContentView: View {
	@ObservedObject private var display = Display.observable

	var body: some View {
		Text(display.wrappedValue.text)
	}
}
```
*/
final class ObservableValue<Value>: ObservableObject {
	let objectWillChange = ObservableObjectPublisher()
	private var publisher: AnyCancellable?
	private(set) var wrappedValue: Value

	init(value: Value, publisher: some Publisher) {
		self.wrappedValue = value

		self.publisher = publisher.sink(
			receiveCompletion: { _ in },
			receiveValue: { [weak self] _ in
				self?.objectWillChange.send()
			}
		)
	}
}
/**
A scrollable and editable text view.

- Note: This exist as the SwiftUI `TextField` is unusable for multiline purposes.

It supports the `.lineLimit()` view modifier.

```
struct ContentView: View {
	@State private var text = ""

	var body: some View {
		VStack {
			Text(String(localized: "Custom CSS:"))
			ScrollableTextView(text: $text)
				.frame(height: 100)
		}
	}
}
```
*/
struct ScrollableTextView: NSViewRepresentable {
	typealias NSViewType = NSScrollView

	final class Coordinator: NSObject, NSTextViewDelegate {
		let view: ScrollableTextView

		init(_ view: ScrollableTextView) {
			self.view = view
		}

		func textDidChange(_ notification: Notification) {
			guard let textView = notification.object as? NSTextView else {
				return
			}

			view.text = textView.string
		}
	}

	@Binding var text: String
	var font = NSFont.controlContentFont(ofSize: 0)
	var isAutomaticQuoteSubstitutionEnabled = true
	var isAutomaticDashSubstitutionEnabled = true
	var isAutomaticTextReplacementEnabled = true
	var isAutomaticSpellingCorrectionEnabled = true

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: Context) -> NSViewType {
		let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
		scrollView.borderType = .bezelBorder

		let textView = scrollView.documentView as! NSTextView
		textView.delegate = context.coordinator
		textView.drawsBackground = false
		textView.isEditable = true
		textView.isSelectable = true
		textView.allowsUndo = true
		textView.textContainerInset = CGSize(width: 5, height: 10)
		textView.textColor = .controlTextColor

		return scrollView
	}

	func updateNSView(_ nsView: NSViewType, context: Context) {
		let textView = (nsView.documentView as! NSTextView)

		if text != textView.string {
			textView.string = text
		}

		textView.font = font

		if let lineLimit = context.environment.lineLimit {
			textView.textContainer?.maximumNumberOfLines = lineLimit
		}

		textView.isAutomaticQuoteSubstitutionEnabled = isAutomaticQuoteSubstitutionEnabled
		textView.isAutomaticDashSubstitutionEnabled = isAutomaticDashSubstitutionEnabled
		textView.isAutomaticTextReplacementEnabled = isAutomaticTextReplacementEnabled
		textView.isAutomaticSpellingCorrectionEnabled = isAutomaticSpellingCorrectionEnabled
	}
}
/**
A view that doesn't accept any mouse events.
*/
// TODO: I plan to extract this into a Swift Package when it's been battle-tested.
/**
This always requests the permission to a directory. If you give it file URL, it will ask for permission to the parent directory.
*/
enum SecurityScopedBookmarkManager {
	private static let lock = NSLock()

	// TODO: Abstract this to a generic class to have a Dictionary like thing that is synced to UserDefaults and the subclass it here.
	private final class BookmarksUserDefaults: @unchecked Sendable {
		// TODO: This should probably be an argument to init.
		private let userDefaultsKey = Defaults.Key<[String: Data]>("__securityScopedBookmarks__", default: [:])

		private var bookmarkStore: [String: Data] {
			get { Defaults[userDefaultsKey] }
			set {
				Defaults[userDefaultsKey] = newValue
			}
		}

		subscript(url: URL) -> Data? {
			// Resolving symlinks is important for normalization. For example, sometimes a reference to the Desktop directory is pointed at a symlink in the sandbox container: `file:///Users/sindresorhus/Library/Containers/com.sindresorhus.Plash/Data/Desktop/`.
			get { bookmarkStore[url.resolvingSymlinksInPath().absoluteString] }
			set {
				var bookmarks = bookmarkStore
				bookmarks[url.resolvingSymlinksInPath().absoluteString] = newValue
				bookmarkStore = bookmarks
			}
		}
	}

	private final class NSOpenSavePanelDelegateHandler: NSObject, NSOpenSavePanelDelegate {
		let currentURL: URL

		init(url: URL) {
			// It's important to resolve symlinks so it doesn't use the sandbox URL.
			self.currentURL = url.resolvingSymlinksInPath()
			super.init()
		}

		/*
		We only allow this directory.

		You might think we could use `didChangeToDirectoryURL` and set `sender.directoryURL = currentURL` there, but that doesn't work. The directory cannot be programmatically changed after the panel is opened.
		*/
		func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
			url == currentURL
		}

		// This should in theory not be needed as we already disable the “Allow” button, but just in case.
		func panel(_ sender: Any, validate url: URL) throws {
			if url != currentURL {
				throw NSError.appError(
					String(localized: "Incorrect directory."),
					recoverySuggestion: "Select the directory “\(currentURL.tildePath)”."
				)
			}
		}
	}

	private static let bookmarks = BookmarksUserDefaults()

	/**
	Save the bookmark.
	*/
	static func saveBookmark(for url: URL) throws {
		bookmarks[url] = try url.accessSecurityScopedResource {
			try $0.bookmarkData(options: .withSecurityScope)
		}
	}

	/**
	Load the bookmark.

	Returns `nil` if there's no bookmark for the given URL or if the bookmark cannot be loaded.
	*/
	static func loadBookmark(for url: URL) -> URL? {
		guard let bookmarkData = bookmarks[url] else {
			return nil
		}

		var isBookmarkDataStale = false

		guard
			let newUrl = try? URL(
				resolvingBookmarkData: bookmarkData,
				options: .withSecurityScope,
				bookmarkDataIsStale: &isBookmarkDataStale
			)
		else {
			return nil
		}

		if isBookmarkDataStale {
			guard (try? saveBookmark(for: newUrl)) != nil else {
				return nil
			}
		}

		return newUrl
	}

	/**
	Returns `nil` if the user didn't give permission or if the bookmark couldn't be saved.
	*/
	@MainActor
	static func promptUserForPermission(
		atDirectory directoryURL: URL,
		message: String? = nil
	) -> URL? {
		lock.lock()

		defer {
			lock.unlock()
		}

		let delegate = NSOpenSavePanelDelegateHandler(url: directoryURL)

		let openPanel = with(NSOpenPanel()) {
			$0.identifier = .init("SecurityScopedBookmarkManager")
			$0.delegate = delegate
			$0.directoryURL = directoryURL
			$0.allowsMultipleSelection = false
			$0.canChooseDirectories = true
			$0.canChooseFiles = false
			$0.canCreateDirectories = false
			$0.title = String(localized: "Permission")
			$0.message = message ?? "\(SSApp.name) needs access to the “\(directoryURL.lastPathComponent)” directory. Click “Allow” to proceed."
			$0.prompt = String(localized: "Allow")
		}

		SSApp.activateIfAccessory()

		guard openPanel.runModal() == .OK else {
			return nil
		}

		guard let securityScopedURL = openPanel.url else {
			return nil
		}

		do {
			try saveBookmark(for: securityScopedURL)
		} catch {
			error.presentAsModal()
			return nil
		}

		return securityScopedURL
	}



	/**
	Accepts a file URL to a directory or file. If it's a file, it will prompt for permissions to its containing directory.

	You have to manually call the returned method when you no longer need access to the URL.
	*/
	@MainActor
	@discardableResult
	static func accessURLByPromptingIfNeeded(_ url: URL) -> (() -> Void) {
		let directoryURL = url.directoryURL

		guard let securityScopedURL = loadBookmark(for: directoryURL) ?? promptUserForPermission(atDirectory: directoryURL) else {
			return {}
		}

		_ = securityScopedURL.startAccessingSecurityScopedResource()

		return {
			securityScopedURL.stopAccessingSecurityScopedResource()
		}
	}
}
/**
```
let x = ["a", "", "b"].filter(!\.isEmpty)

print(x)
//=> ["a", "b"]
```
*/
prefix func ! <Root>(rhs: KeyPath<Root, Bool>) -> (Root) -> Bool { // swiftlint:disable:this static_operator
	{ !$0[keyPath: rhs] }
}
/**
Wrapper around `NSCache` that enables using any hashable key and any value.
*/
final class Cache<Key: Hashable, Value> {
	private final class WrappedKey: NSObject {
		let key: Key

		init(key: Key) {
			self.key = key
		}

		override var hash: Int { key.hashValue }

		override func isEqual(_ object: Any?) -> Bool {
			guard let value = object as? Self else {
				return false
			}

			return value.key == key
		}
	}

	private final class WrappedValue {
		let value: Value

		init(value: Value) {
			self.value = value
		}
	}

	private let cache = NSCache<WrappedKey, WrappedValue>()

	/**
	Get, set, or remove an entry from the cache.
	*/
	subscript(key: Key) -> Value? {
		get { cache.object(forKey: .init(key: key))?.value }
		set {
			guard let newValue else {
				// If the value is `nil`, remove the entry from the cache.
				cache.removeObject(forKey: .init(key: key))

				return
			}

			cache.setObject(.init(value: newValue), forKey: .init(key: key))
		}
	}

	/**
	Removes all entries.
	*/
	func removeAll() {
		cache.removeAllObjects()
	}
}
// TODO: Rewrite as an actor.
/**
Extremely simple and naive image cache.

The cache is thread-safe.

You can optionally persist the cache to disk. Reading from the cache is synchronous. Saving to the cache happens asynchronously in a background thread.
*/
final class SimpleImageCache<Key: SimpleImageCacheKeyable> {
	private let lock = OSAllocatedUnfairLock()
	private let diskQueue = DispatchQueue(label: "SimpleImageCache")
	private let cache = Cache<Key, NSImage>()
	private var cacheDirectory: URL?

	private var shouldUseDisk: Bool { cacheDirectory != nil }

	/**
	- Parameter diskCacheName: If you want to cache to disk, pass a name. The name should be a valid directory name.
	*/
	init(diskCacheName: String? = nil) {
		if let diskCacheName {
			do {
				self.cacheDirectory = try createCacheDirectory(name: diskCacheName)
			} catch {
				assertionFailure("Failed to create cache directory: \(error)")
			}
		}
	}

	private func createCacheDirectory(name: String) throws -> URL {
		let rootCacheDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

		let cacheDirectory = rootCacheDirectory
			.appendingPathComponent(SSApp.name, isDirectory: true)
			.appendingPathComponent(name, isDirectory: true)

		try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

		return cacheDirectory
	}

	private func createCacheDirectoryIfNeeded() {
		guard let cacheDirectory else {
			return
		}

		try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
	}

	private func cacheFileFromKey(_ key: Key) -> URL? {
		cacheDirectory?.appendingPathComponent(key.cacheKey.sha256(), isDirectory: false)
	}

	private func loadImageFromDiskIfNeeded(for key: Key) -> NSImage? {
		guard
			shouldUseDisk,
			let cacheFile = cacheFileFromKey(key)
		else {
			return nil
		}

		return NSImage(contentsOf: cacheFile)
	}

	private func saveImageToDiskIfNeeded(_ image: NSImage, for key: Key) {
		guard
			shouldUseDisk,
			let cacheFile = cacheFileFromKey(key)
		else {
			return
		}

		diskQueue.async { [weak self] in
			guard let self else {
				return
			}

			guard let tiffData = image.tiffRepresentation else {
				assertionFailure("Could not get TIFF representation from image.")
				return
			}

			// Ensure the cache directory exists in case it was removed by `.removeAllImages()` or the user.
			createCacheDirectoryIfNeeded()

			do {
				try tiffData.write(to: cacheFile)
			} catch {
				assertionFailure("Failed to write image to disk: \(error.localizedDescription)")
			}
		}
	}

	private func removeImageFromDiskIfNeeded(for key: Key) {
		guard
			shouldUseDisk,
			let cacheFile = cacheFileFromKey(key)
		else {
			return
		}

		diskQueue.async {
			try? FileManager.default.removeItem(at: cacheFile)
		}
	}

	private func removeAllImagesFromDiskIfNeeded() {
		guard
			shouldUseDisk,
			let cacheDirectory
		else {
			return
		}

		diskQueue.async {
			try? FileManager.default.removeItem(at: cacheDirectory)
		}
	}

	/**
	Get the image for the given key.
	*/
	private func image(for key: Key) -> NSImage? {
		lock.lock()
		defer {
			lock.unlock()
		}

		guard let image = cache[key] else {
			guard let image = loadImageFromDiskIfNeeded(for: key) else {
				return nil
			}

			cache[key] = image

			return image
		}

		return image
	}

	/**
	Insert an image into the cache for the given key.
	*/
	private func insertImage(_ image: NSImage?, for key: Key) {
		guard let image else {
			removeImage(for: key)
			return
		}

		lock.lock()
		defer {
			lock.unlock()
		}

		cache[key] = image
		saveImageToDiskIfNeeded(image, for: key)
	}

	/**
	Remove an image from the cache for the given key.
	*/
	private func removeImage(for key: Key) {
		lock.lock()
		defer {
			lock.unlock()
		}

		cache[key] = nil
		removeImageFromDiskIfNeeded(for: key)
	}

	/**
	If the cache items exists on disk but not in the memory cache, this adds it them the memory cache too.

	This is run in a background thread.
	*/
	func prewarmCacheFromDisk(for keys: [Key]) {
		DispatchQueue.global().async { [self] in
			for key in keys {
				_ = image(for: key)
			}
		}
	}

	/**
	Remove all images from the cache.
	*/
	func removeAllImages() {
		lock.lock()
		defer {
			lock.unlock()
		}

		cache.removeAll()
		removeAllImagesFromDiskIfNeeded()
	}

	/**
	Get, set, or remove an image from the cache.
	*/
	subscript(_ key: Key) -> NSImage? {
		get { image(for: key) }
		set {
			guard let newValue else {
				removeImage(for: key)
				return
			}

			insertImage(newValue, for: key)
		}
	}
}
/**
Circular button with question mark that shows a popover with the given content when tapped.

The content has automatic padding.
*/
struct InfoPopoverButton<Content: View>: View {
	@State private var isPopoverPresented = false

	var maxWidth: Double?
	@ViewBuilder let content: Content

	var body: some View {
		CocoaButton("", bezelStyle: .helpButton) {
			isPopoverPresented = true
		}
		.popover(isPresented: $isPopoverPresented) {
			content
				.controlSize(.regular) // Setting control size on the button should not affect the content.
				.padding()
				.multilineText()
				.ifLet(maxWidth) {
					// TODO: `maxWidth` doesn't work. Causes the popover to me infinite height. (macOS 11.2.3)
					$0.frame(width: $1)
				}
		}
	}
}
// TODO: Make it an actor.
// TODO: Ensure it still works well. Try disabling the LinkPresentation API and caching.
/*
TODO when Swift 5.5 is out:
- Support more ways to get the icon: https://stackoverflow.com/a/22007642/64949
- Get all icons concurrently.
- Recreate the webview for each request.
- Use only a single `evaluateJavaScript` call.
- Run on DOM-ready instad of when the whole page has loaded.
	- If not possible, block all subresources: https://stackoverflow.com/questions/32119975/how-to-block-external-resources-to-load-on-a-wkwebview
- Make the thumbnail in WebsitesScreen not upscale when using 32x32 favicon.
- Support specifying target size and have it return the one closest above the target size, if any.
- Use the icons in the "Switch" menu.
*/
@MainActor
final class WebsiteIconFetcher: NSObject {
	private struct WebAppManifestIcon {
		let url: URL
		let size: CGSize?

		init?(_ dictionary: [String: String]) {
			guard
				// TODO: Handle relative URLs: https://developer.mozilla.org/en-US/docs/Web/Manifest/icons
				let urlString = dictionary["src"],
				let url = URL(string: urlString)
			else {
				return nil
			}

			self.url = url

			// TODO: Handle there being multiple space-separated sizes.
			self.size = if
				let sizeString = dictionary["sizes"]?.split(separator: " ").first,
				let size = CGSize.from(dimensions: String(sizeString))
			{
				size
			} else {
				nil
			}
		}
	}

	@MainActor
	static func fetch(for url: URL) async throws -> NSImage? {
		guard url.isValid else {
			throw NSError.appError("Invalid URL: \(url.absoluteString)")
		}

		return try await self.init().fetch(for: url)
	}

	@MainActor
	private lazy var webView: WKWebView = {
		let configuration = WKWebViewConfiguration()

		let userContentController = WKUserContentController()
		configuration.userContentController = userContentController

		let preferences = WKPreferences()
		preferences.javaScriptCanOpenWindowsAutomatically = false
		configuration.preferences = preferences

		let webView = WKWebView(frame: .zero, configuration: configuration)
		webView.navigationDelegate = self
		webView.customUserAgent = SSWebView.safariUserAgent

		return webView
	}()

	private var url: URL?
	private var continuation: CheckedContinuation<Void, Error>?

	private func getImage(_ url: URL) async throws -> NSImage? {
		let (data, _) = try await URLSession.shared.data(from: url)
		return NSImage(data: data)
	}

	private func getFavicon() async throws -> NSImage? {
		guard
			let faviconURL = URL(string: "favicon.ico", relativeTo: url)
		else {
			return nil
		}

		return try await getImage(faviconURL)
	}

	private func getFromLPMetadataProvider(url: URL) async throws -> NSImage? {
		let metadata = try await LPMetadataProvider().startFetchingMetadata(for: url)

		guard
			let iconProvider = metadata.iconProvider,
			iconProvider.hasItemConforming(to: .image)
		else {
			return nil
		}

		return await iconProvider.getImage()
	}

	// TODO: This is moot as the class is marked as `@MainActor`, but we keep it for now just in case.
	@MainActor
	private func getFromManifest() async throws -> NSImage? {
		let code =
			"""
			document.querySelector('link[rel="manifest"]').href
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		let (data, _) = try await URLSession.shared.data(from: url)

		guard
			let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
			let icons = json["icons"] as? [[String: String]]
		else {
			return nil
		}

		let iconStructs = icons.compactMap { WebAppManifestIcon($0) }

		// TODO: Instead of picking the largest one, we should download all and add them as representations to a single `NSImage`.
		guard
			let largestIcon = (iconStructs.max { ($0.size?.width ?? 0) < ($1.size?.width ?? 0) })
		else {
			return nil
		}

		return try await getImage(largestIcon.url)
	}

	@MainActor
	private func getFromLinkIcon() async throws -> NSImage? {
		// TODO: There can be multiple of this one, some with larger sizes specified in a `sizes` prop.
		// The `~` is because of the `shortcut` link type, which is often seen before icon, but this link type is non-conforming, ignored and web authors must not use it anymore: https://developer.mozilla.org/en-US/docs/Web/HTML/Link_types
		let code =
			"""
			document.querySelector('link[rel~="icon"]').href
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		return try await getImage(url)
	}

	@MainActor
	private func getFromMetaItemPropImage() async throws -> NSImage? {
		let code =
			"""
			new URL(document.querySelector('meta[itemprop="image"]').content, document.baseURI).toString()
			"""

		let result = try await webView.evaluateJavaScript(code, contentWorld: .defaultClient)

		guard
			let urlString = result as? String,
			let url = URL(string: urlString)
		else {
			return nil
		}

		return try await getImage(url)
	}

	@MainActor
	private func fetch(for url: URL) async throws -> NSImage? {
		self.url = url

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalCacheData

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			self.continuation = continuation
			webView.load(request)
		}

		// TODO: Use `??` for all of these when `??` supports await.

		if let image = try? await getFromLPMetadataProvider(url: url) {
			return image
		}

		if let image = try? await getFromManifest() {
			return image
		}

		if let image = try? await getFromMetaItemPropImage() {
			return image
		}

		if let image = try? await getFromLinkIcon() {
			return image
		}

		if let image = try? await getFavicon() {
			return image
		}

		return nil
	}
}
/**
A helper that converts a binding to a collection of elements into a collection of bindings to the individual elements.
*/
struct BindingCollection<Base: MutableCollection & RandomAccessCollection>: RandomAccessCollection {
	let base: Binding<Base>

	typealias Element = Binding<Base.Element>
	typealias Index = Base.Index

	var startIndex: Index { base.wrappedValue.startIndex }
	var endIndex: Index { base.wrappedValue.endIndex }

	subscript(position: Base.Index) -> Binding<Base.Element> {
		Binding(
			get: { base.wrappedValue[position] },
			set: {
				var result = base.wrappedValue
				result[position] = $0
				base.wrappedValue = result
			}
		)
	}

	func index(before index: Base.Index) -> Base.Index {
		base.wrappedValue.index(before: index)
	}

	func index(after index: Base.Index) -> Base.Index {
		base.wrappedValue.index(after: index)
	}
}
