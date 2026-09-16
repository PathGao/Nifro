@preconcurrency import WebKit
@preconcurrency import LinkPresentation
import SwiftUI
import Combine
import CryptoKit
import UniformTypeIdentifiers
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

	let title: String
	let bezelStyle: NSButton.BezelStyle
	let action: () -> Void

	init(
		_ title: String,
		bezelStyle: NSButton.BezelStyle = .rounded,
		action: @escaping () -> Void
	) {
		self.title = title
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
		nsView.title = title
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
	Present the error as a blocking app-level modal dialog.

	Off the calling turn through `DispatchQueue.main.async`, which is a workaround rather than a thread
	hop: presenting straight from the caller does not work reliably ([FB9857161](https://github.com/feedback-assistant/reports/issues/288)),
	the same report `NSAlert.run()` further down is built around. The direct version stood here as three
	commented-out lines waiting on that report, so it is the workaround that is the code.

	App-modal is the only way this presents. The window-modal half — `presentAsSheet(for:)`, the
	`NSResponder` glue under it and the `present(in:)` that chose between the two — went because no
	call site in this repo's history ever passed a window: it arrived whole with the upstream shared
	utilities file and every caller took the `nil` default. Attaching an error to a window is a
	capability to be written, not one to be switched back on.
	*/
	@MainActor
	func presentAsModal() {
		DispatchQueue.main.async {
			SSApp.activateIfAccessory()
			NSApp.presentError(self)
		}
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
	var isCancelled: Bool {
		do {
			throw self
		} catch is CancellationError, URLError.cancelled, CocoaError.userCancelled {
			return true
		} catch {
			return false
		}
	}
}

// MARK: - InfoPopoverButton
extension InfoPopoverButton<Text> {
	init(_ text: some StringProtocol, maxWidth: Double = 240) {
		self.content = Text(text)
		self.maxWidth = maxWidth
	}
}

// MARK: - KeyedDecodingContainer
extension KeyedDecodingContainer {
	/**
	Let a `@DecodableDefault` field fall back to its default when the key is absent.

	Without this the wrapper only defaults a key that is *present and null*, which is the one case
	that never happens: the case it exists for is a field added to a type after something was already
	stored, so every record written before it simply has no such key. The synthesised `init(from:)`
	calls `decode(_:forKey:)`, that throws `keyNotFound`, and because the whole array is one
	`Defaults` value, one old record takes every website with it — the list comes back empty and the
	app looks like a fresh install.

	This is the overload the property wrapper was designed around; an earlier cleanup removed it when
	it happened to have no members, and adding `externalLinks` to `Website` in #53 was the first field
	added since. `WebsiteDecodingTests` pins the behaviour rather than the presence of this code.
	*/
	// periphery:ignore - The only caller is a synthesised `init(from:)`, which no index attributes to
	// this overload. That invisibility is not a footnote here: it is why the extension holding this was
	// deleted once as an empty shell, and deleting it empties every user's website list on the next
	// field added to `Website`. Reported by the scan, argued here, and not to be quieted any other way.
	func decode<T>(_ type: DecodableDefault.Wrapper<T>.Type, forKey key: Key) throws -> DecodableDefault.Wrapper<T> {
		try decodeIfPresent(type, forKey: key) ?? .init()
	}
}

// MARK: - LPLinkMetadata
extension LPLinkMetadata: @retroactive @unchecked Sendable {}

// MARK: - LPMetadataProvider
extension LPMetadataProvider: @retroactive @unchecked Sendable {}

// MARK: - NSAlert
extension NSAlert {
	/**
	Show an app-modal alert from an `async` context, resuming when it is dismissed.
	*/
	@discardableResult
	static func show(
		title: LocalizedStringResource,
		message: LocalizedStringResource? = nil,
		style: Style = .warning,
		buttonTitles: [LocalizedStringResource] = [],
		defaultButtonIndex: Int? = nil
	) async -> NSApplication.ModalResponse {
		await NSAlert(
			title: title,
			message: message,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex
		)
		.run()
	}

	/**
	Show an app-modal alert, blocking until it is dismissed.

	The synchronous twin of `show`, which is the one to reach for from a `Task`.
	*/
	@discardableResult
	static func showModal(
		title: LocalizedStringResource,
		message: LocalizedStringResource? = nil,
		style: Style = .warning,
		buttonTitles: [LocalizedStringResource] = [],
		defaultButtonIndex: Int? = nil
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title,
			message: message,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex
		)
		.runModal()
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
		title: LocalizedStringResource,
		message: LocalizedStringResource? = nil,
		style: Style = .warning,
		buttonTitles: [LocalizedStringResource] = [],
		defaultButtonIndex: Int? = nil
	) {
		self.init()
		self.messageText = String(localized: title)
		self.alertStyle = style

		if let message {
			self.informativeText = String(localized: message)
		}

		addButtons(withTitles: buttonTitles)

		if let defaultButtonIndex {
			self.defaultButtonIndex = defaultButtonIndex
		}
	}

	/**
	Adds buttons with the given titles to the alert.

	`LocalizedStringResource` rather than `String`, which is the point of this method existing rather
	than `addButton(withTitle:)` being called directly. AppKit's own takes a `String`, so a literal and
	a translated string have the same type there and nothing can tell them apart — which is how three
	alerts in this file ended up with a localized "Log In" beside a hardcoded "Cancel". Here a literal
	at the call site is a key: the compiler refuses a plain `String`, and Xcode extracts the literal
	into the catalogue on its own.
	*/
	func addButtons(withTitles buttonTitles: [LocalizedStringResource]) {
		for buttonTitle in buttonTitles {
			addButton(withTitle: String(localized: buttonTitle))
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
		_ description: LocalizedStringResource,
		recoverySuggestion: LocalizedStringResource? = nil,
		userInfo: [String: Any] = [:],
		domainPostfix: String? = nil
	) -> Self {
		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = String(localized: description)

		if let recoverySuggestion {
			userInfo[NSLocalizedRecoverySuggestionErrorKey] = String(localized: recoverySuggestion)
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

// MARK: - String
extension String {
	var trimmed: Self {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func removingPrefix(_ prefix: Self) -> Self {
		guard hasPrefix(prefix) else {
			return self
		}

		return Self(dropFirst(prefix.count))
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
			let sawMedia = false;

			const adopt = element => {
				sawMedia = true;
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

			// A full rescan is needed as well as muting on insertion: a player can reuse an element and
			// set `muted` back on it in place, which produces no mutation of its own, so the rescan is
			// what re-asserts the setting. But this script is in every page and every frame, a live
			// stream's chat fires mutations continuously, and the rescan reads the whole document — so a
			// page with no media on it at all was scanning up to sixty times a second for as long as it
			// stayed on screen, which is the entire life of a wallpaper. Hence both brakes. One rescan
			// per frame collapses a burst into a single pass, and `sawMedia` means a page that has never
			// held a media element never scans. The first element on a page is not what the rescan is
			// for: insertion and reparenting both arrive as added nodes, and the walk below reaches the
			// same elements `document.querySelectorAll` would.
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

				if (sawMedia && !rescanQueued) {
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

	A hardcoded version goes stale. Sites that gate on it start showing "your browser is out of date" a year or two after release, which is what happened to Google Calendar here for two years. Safari's marketing version has tracked the macOS major version since macOS 26, so deriving it from the running system costs nothing and keeps up.
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
		// Percent-encoded here and decoded in the page, which is what lets the CSS carry quotes, backslashes and newlines through a JavaScript string literal without escaping any of them itself.
		//
		// `decodeURIComponent` on the other side, and not `unescape`. Each of those has a partner and they are not the same one: `unescape` is the inverse of `escape`, and both read a `%XX` as a single Latin-1 character, while `addingPercentEncoding` writes the UTF-8 bytes and only `decodeURIComponent` reads them back as UTF-8. Pairing one half of each corrupted every non-ASCII codepoint there is — Foundation percent-encodes non-ASCII whatever the allowed set says, so this was never about one language — and left ASCII untouched, that being the overlap where the two conventions agree and the reason the damage looked random rather than total.
		let textContent = css.addingPercentEncoding(withAllowedCharacters: .letters) ?? css

		// Injected at document start, so the style element gets appended to a document the page has not finished building. Frameworks that swap out `documentElement` or clear `head` on mount take our style with them, and the user's CSS stops applying. People report this as "my CSS works in Safari but not here".
		//
		// Re-appending on mutation is the fix, and re-appending the same element is a move rather than a duplicate.
		//
		// `childList` on `document` and on `documentElement`, and no `subtree`. Those are the only two parents the style can go missing from, because the only place it is ever put is `head ?? documentElement`. Watching the whole document instead — which is what this did, while the line above claimed otherwise — means every node inserted or removed anywhere on the page wakes the callback, once for each stylesheet injected and once per frame, for as long as the wallpaper is up. A page with a live feed on it pays that continuously to answer a question about two nodes.
		return
			"""
			(() => {
				const style = document.createElement('style');
				style.textContent = decodeURIComponent('\(textContent)');
				style.dataset.nifroInjected = 'css';

				let observer;

				const attach = () => {
					const root = document.head ?? document.documentElement;

					if (root && style.parentNode !== root) {
						root.appendChild(style);
					}

					// Re-armed on every attach rather than armed once: a framework that replaces
					// `documentElement` leaves the old registration watching a node that is no longer
					// in the document. Observing a node that is already observed replaces its options
					// instead of adding a second registration, so this does not accumulate.
					if (document.documentElement) {
						observer.observe(document.documentElement, { childList: true });
					}
				};

				observer = new MutationObserver(attach);
				observer.observe(document, { childList: true });

				attach();
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

	On the type rather than on a web view. It touches no web view and reaches every store the app has,
	so hanging it off one made callers reach for a web view they had no other use for.
	*/
	static func clearAllWebsiteData() async {
		HTTPCookieStorage.shared.removeCookies(since: .distantPast)

		// By date, not by record. Removing "for: records" only reaches what WebKit can attribute to an
		// origin, and the disk cache is mostly not: measured after a clear, `Caches/WebKit/NetworkCache`
		// still held 315MB in 1158 files, none of them rewritten since. A button that says it clears
		// website data has to have cleared it.
		for store in await DiskBudget.allStores() {
			await store.removeData(ofTypes: allWebsiteDataTypes(), modifiedSince: .distantPast)
		}
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
		// The page's own text, verbatim on purpose — it is not ours and there is nothing to translate.
		alert.messageText = message
		alert.addButtons(withTitles: ["OK", "Cancel"])
		return await alert.run() == .alertFirstButtonReturn
	}

	/**
	Default handler for JavaScript `prompt()` to be used in `WKDelegate`.
	*/
	func defaultPromptHandler(prompt: String, defaultText: String?) async -> String? {
		let alert = NSAlert()
		alert.alertStyle = .informational
		// The page's own text, verbatim on purpose — it is not ours and there is nothing to translate.
		alert.messageText = prompt
		alert.addButtons(withTitles: ["OK", "Cancel"])

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
		alert.messageText = String(localized: "Log in to \(host)")
		alert.addButtons(withTitles: ["Log In", "Cancel"])

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
