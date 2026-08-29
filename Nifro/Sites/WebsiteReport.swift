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
			"Region: \(zoom.summaryText)",
			// Same rule as the reload interval below: what this website does, plus where the answer came
			// from when it is not the website's own.
			"External links: \(opensExternalLinksInBrowser ? "browser" : "in Nifro")\(externalLinks == .followSettings ? " (from Settings)" : "")",
			"Invert colours: \(invertColors2.title)",
			"Print styles: \(usePrintStyles ? "yes" : "no")"
		]

		if let startHour, let endHour {
			lines.append(String(format: "Hours: %02d:00–%02d:00", startHour, endHour))
		}

		lines.append("Custom CSS: \(describe(customCSS))")
		lines.append("Custom JavaScript: \(describe(customJavaScript))")

		// The website's own interval when it has one, otherwise the one it inherits from Settings. The
		// report has to say what this website does, not what the settings window says.
		if let reloadInterval = effectiveReloadInterval {
			lines.append("Reload every: \(Int(reloadInterval / 60)) min\(self.reloadInterval == nil ? " (from Settings)" : "")")
		}

		return lines.joined(separator: "\n")
	}

	private func describe(_ code: String?) -> String {
		guard let code else {
			return "none"
		}

		return "\(code.trimmed.components(separatedBy: .newlines).count) lines"
	}
}
