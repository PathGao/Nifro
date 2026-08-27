import AppKit
import os

// Moved out of Extensions.swift, which is where it was only because everything was. This is a
// component, not an extension.

// MARK: - SimpleImageCacheKeyable
protocol SimpleImageCacheKeyable: Hashable {
	var cacheKey: String { get }
}

extension String: SimpleImageCacheKeyable {
	var cacheKey: String { self }
}

extension URL: SimpleImageCacheKeyable {
	var cacheKey: String { absoluteString }
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
	- Parameter totalCostLimit: The budget the costs passed to `setValue` are spent against. Required
	rather than defaulted, because `NSCache`'s own default is no limit at all and a cache that grows
	for the lifetime of the process is what this class was for four years.
	*/
	init(totalCostLimit: Int) {
		cache.totalCostLimit = totalCostLimit
	}

	/**
	Get an entry from the cache.
	*/
	subscript(key: Key) -> Value? {
		cache.object(forKey: .init(key: key))?.value
	}

	/**
	Insert an entry, saying what holding it costs against the budget.

	The cost is not optional and there is no setter without it, so an entry cannot be added that the
	budget cannot see. `NSCache` charges nothing for an object inserted with no cost and evicts on the
	total, which makes a partly-costed cache unbounded rather than approximate.
	*/
	func setValue(_ value: Value, for key: Key, cost: Int) {
		cache.setObject(.init(value: value), forKey: .init(key: key), cost: cost)
	}

	/**
	Remove an entry from the cache.
	*/
	func removeValue(for key: Key) {
		cache.removeObject(forKey: .init(key: key))
	}

	/**
	Removes all entries.
	*/
	func removeAll() {
		cache.removeAllObjects()
	}
}

/**
What the in-memory half of `SimpleImageCache` is allowed to hold.

These entries are website thumbnails drawn at 44×44 in one window, but they are stored at whatever
size they arrived at — often video cover art, which is 1280×720. Measured the way `cost` measures, that
is 3.7 MB apiece against 92 KB for a 152×152 site icon and 4 KB for a favicon, so this is about nine
covers or three hundred favicons, and rather more in real resident bytes because `cost` over-counts.
Past it the oldest entries go and the next draw reads the file again, which is the path
`IconView.fetchIcons` already takes on a miss.

A number at all is the point. There was none, so the ceiling was "every distinct address the list has
ever held", for the lifetime of the process, in an app whose window this is behind.

Outside the type because a generic one cannot hold a stored static.
*/
private let imageCacheMemoryLimit = 32_000_000

// TODO: Rewrite as an actor.
/**
Extremely simple and naive image cache.

The cache is thread-safe.

You can optionally persist the cache to disk. Reading from the cache is synchronous. Saving to the cache happens asynchronously in a background thread.
*/
final class SimpleImageCache<Key: SimpleImageCacheKeyable> {
	private let lock = OSAllocatedUnfairLock()
	private let diskQueue = DispatchQueue(label: "SimpleImageCache")
	private let cache = Cache<Key, NSImage>(totalCostLimit: imageCacheMemoryLimit)
	private var cacheDirectory: URL?

	/**
	What holding this image is charged against the budget.

	Its fully decoded size, which is an upper bound rather than a measurement: `NSImage` keeps what it
	was made from and decodes at draw, so a 1280×720 cover that this counts as 3.7 MB was measured
	resident at 2.8 MB while its file on disk was TIFF, and less again once the same file is smaller.
	Over-counting is the safe direction for a ceiling, and asking for the truth means materialising a
	representation, which is the allocation the budget exists to avoid. Reading the pixel dimensions
	forces no decode — measured at zero additional bytes for twenty images.
	*/
	private static func cost(of image: NSImage) -> Int {
		guard let representation = image.representations.first else {
			return 0
		}

		return representation.pixelsWide * representation.pixelsHigh * 4
	}

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
				// Atomic because the read is `NSImage(contentsOf:)` on another queue with nothing
				// between them: a torn file is decoded as a broken image, cached in memory as if it
				// were the real one, and read back the same way on every launch after. There is no
				// path that notices and refetches, so one interrupted write is a permanently blank
				// square in the websites list.
				try tiffData.write(to: cacheFile, options: .atomic)
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

			cache.setValue(image, for: key, cost: Self.cost(of: image))

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

		cache.setValue(image, for: key, cost: Self.cost(of: image))
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

		cache.removeValue(for: key)
		removeImageFromDiskIfNeeded(for: key)
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
