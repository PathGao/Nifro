import SwiftUI

/**
A length of time, entered as a number and a unit.

The field used to be minutes and nothing else, so a website that reloads once a day read as “1440
minutes”. Nobody reads that as a day. The unit now follows the value: the field opens on the largest
unit that expresses it exactly, so a day arrives as 24 hours and ninety seconds stays 90 seconds.

Stops at hours. `UnitDuration` has no day, and inventing one would mean naming it ourselves in every
language, where the three built-in units come already translated.
*/
struct IntervalField: View {
	@Binding var seconds: Double

	@State private var chosenUnit: UnitDuration?

	private static let units: [UnitDuration] = [.seconds, .minutes, .hours]

	@MainActor
	private static let unitNames: MeasurementFormatter = {
		let formatter = MeasurementFormatter()
		formatter.unitStyle = .long
		formatter.unitOptions = .providedUnit
		return formatter
	}()

	var body: some View {
		HStack {
			TextField("", value: amount, format: .number.grouping(.never).precision(.fractionLength(0)))
				.labelsHidden()
				.frame(width: 44)
			Stepper("", value: amount, in: 1...(.greatestFiniteMagnitude), step: 1)
				.labelsHidden()
			Picker("", selection: unit) {
				ForEach(Self.units, id: \.self) {
					Text(Self.unitNames.string(from: $0)).tag($0)
				}
			}
			.labelsHidden()
			.frame(width: 104)
		}
	}

	private var unit: Binding<UnitDuration> {
		.init(
			get: { chosenUnit ?? Self.largestExactUnit(for: seconds) },
			set: { newUnit in
				// The number stays put and the duration changes, which is how everyone reads “every 5
				// ⟨hours⟩”. Converting instead would turn 5 minutes into 0.08 hours on the way past.
				let value = amount.wrappedValue
				chosenUnit = newUnit
				seconds = Measurement(value: value, unit: newUnit).converted(to: .seconds).value
			}
		)
	}

	private var amount: Binding<Double> {
		.init(
			get: { Measurement(value: seconds, unit: UnitDuration.seconds).converted(to: unit.wrappedValue).value.rounded() },
			set: { seconds = Measurement(value: max(1, $0.rounded()), unit: unit.wrappedValue).converted(to: .seconds).value }
		)
	}

	/**
	The biggest unit this many seconds is a whole number of.
	*/
	private static func largestExactUnit(for seconds: Double) -> UnitDuration {
		units.last {
			let value = Measurement(value: seconds, unit: UnitDuration.seconds).converted(to: $0).value
			return value >= 1 && value == value.rounded()
		} ?? .seconds
	}
}
