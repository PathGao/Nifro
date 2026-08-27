import Foundation

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
