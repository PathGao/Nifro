import SwiftUI

/**
Editor for a website's crop region.

Numbers are page pixels measured from the top-left of the page. The four of them are one setting, not four, so the form treats them that way: cropping is either off or fully specified, and a half-filled crop never reaches the model.
*/
struct CropSetting: View {
	@Binding var crop: CGRect?

	private var isEnabled: Binding<Bool> {
		.init(
			get: { crop != nil },
			set: { crop = $0 ? Self.defaultCrop : nil }
		)
	}

	/**
	A starting region small enough to be obviously a crop, placed away from the corner so it does not look like a mistake.
	*/
	private static let defaultCrop = CGRect(x: 0, y: 0, width: 600, height: 400)

	var body: some View {
		Toggle("Crop to a region", isOn: isEnabled)
			.help("Shows only part of the page, cutting away navigation bars, borders and anything else around the part worth looking at. The window shrinks to the cropped region, so the rest of your desktop stays usable.")

		if crop != nil {
			HStack {
				field("X", value: binding(\.origin.x))
				field("Y", value: binding(\.origin.y))
				field("Width", value: binding(\.size.width))
				field("Height", value: binding(\.size.height))
			}
			.help("Page pixels, measured from the top-left of the page.")
		}
	}

	private func field(_ label: String, value: Binding<Double>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.caption)
				.foregroundStyle(.secondary)
			TextField(label, value: value, format: .number.precision(.fractionLength(0)))
				.labelsHidden()
				.frame(width: 64)
		}
	}

	private func binding(_ keyPath: WritableKeyPath<CGRect, CGFloat>) -> Binding<Double> {
		.init(
			get: { Double(crop?[keyPath: keyPath] ?? 0) },
			set: { newValue in
				guard var crop else {
					return
				}

				// A zero or negative extent would produce a window macOS cannot show, and the user is mid-typing, not asking for that.
				crop[keyPath: keyPath] = max(0, CGFloat(newValue))
				self.crop = crop.standardized
			}
		)
	}
}
