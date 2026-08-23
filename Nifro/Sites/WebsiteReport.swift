import AppKit

extension Website {
	/**
	Everything about this website that changes how it behaves, as text to paste into a bug report.

	A report that says "it does not reload" is unanswerable, and asking for the settings one at a
	time takes a round trip per answer. Nearly every question worth asking about a wallpaper —
	whether it reloads, whether it makes noise, whether the page is even being rendered — is decided
	by the settings on that one website, so this puts all of them in one place the reporter can copy
	without knowing which ones matter.

	Only settings. The address is included because it is the first thing anyone opens; nothing else
	here identifies the person, and custom code is reported by size rather than by content, because a
	stylesheet can carry a private selector and this is copied by people who are about to paste it in
	public.
	*/
	var reportText: String {
		var lines = [
			"\(SSApp.name) \(SSApp.versionWithBuild) · macOS \(Device.osVersion) · \(Device.hardwareModel)",
			"URL: \(url.absoluteString)",
			"Sound: \(audio.title)",
			"Region: \(zoom.map { "\(($0.scale * 10).rounded() / 10)× at \(Int(($0.center.x * 100).rounded()))%, \(Int(($0.center.y * 100).rounded()))%" } ?? "whole page")",
			"Clickable on the desktop: \(allowsInteraction ? "yes" : "no")",
			"Invert colours: \(invertColors2.title)",
			"Print styles: \(usePrintStyles ? "yes" : "no")",
			"Display: \(display?.localizedName ?? "default")"
		]

		if let startHour, let endHour {
			lines.append(String(format: "Hours: %02d:00–%02d:00", startHour, endHour))
		}

		lines.append("Custom CSS: \(describe(css))")
		lines.append("Custom JavaScript: \(describe(javaScript))")

		// The website's own interval when it has one, otherwise the one it inherits from Settings. The
		// report has to say what this website does, not what the settings window says.
		if let reloadInterval = effectiveReloadInterval {
			lines.append("Reload every: \(Int(reloadInterval / 60)) min\(self.reloadInterval == nil ? " (from Settings)" : "")")
		}

		return lines.joined(separator: "\n")
	}

	private func describe(_ code: String) -> String {
		let trimmed = code.trimmed

		guard !trimmed.isEmpty else {
			return "none"
		}

		return "\(trimmed.components(separatedBy: .newlines).count) lines"
	}
}
