import Foundation

extension StringProtocol {
	/**
	Break the string into lines no longer than `length`, at spaces.

	A word longer than the line becomes a line of its own rather than being cut. Whatever is that long
	is usually a URL or an error code, and a URL broken in half is worse than a line that overruns.

	Lives here, with the other pure functions, because the version this replaces shipped a bug for
	years that one test would have caught: a word longer than the line was written out, then written
	again on the next line. Text with no spaces in it — a Chinese sentence, a long identifier — came
	out doubled. It was in `Extensions.swift`, which nothing tests, and that is the only reason
	nobody noticed.
	*/
	func wordWrapped(atLength length: Int) -> String {
		var lines = [String]()
		var line = ""

		for word in components(separatedBy: .whitespaces) where !word.isEmpty {
			if line.isEmpty {
				line = word
			} else if line.count + 1 + word.count <= length {
				line += " \(word)"
			} else {
				lines.append(line)
				line = word
			}
		}

		if !line.isEmpty {
			lines.append(line)
		}

		return lines.joined(separator: "\n")
	}
}

/**
Whether an error means "we stopped this ourselves", rather than "this failed".

Superseding a load cancels the one in flight, and cancelling is how that is done — so the cancelled
task reports an error that is not one. Shown to the user it reads as a fault in the app, and the
wording it arrives with (`Swift.CancellationError error 1`) reads as a fault in the app written by
somebody who did not expect anyone to see it.
*/
func isCancellation(_ error: Error) -> Bool {
	if error is CancellationError {
		return true
	}

	let error = error as NSError

	if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
		return true
	}

	return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
}
