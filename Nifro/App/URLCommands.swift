import Cocoa

extension AppState {
	func setUpURLCommands() {
		SSEvents.appOpenURL
			.sink { [self] in
				handleURLCommands($0)
			}
			.store(in: &cancellables)
	}

	private func handleURLCommands(_ urlComponents: URLComponents) {
		guard urlComponents.scheme == Bundle.main.urlScheme else {
			return
		}

		let command = urlComponents.path
		let parameters = urlComponents.queryDictionary

		func showMessage(_ message: String) {
			SSApp.forceActivate()
			NSAlert.showModal(title: message)
		}

		switch command {
		case "add":
			guard
				let urlString = parameters["url"]?.trimmed,
				let url = URL(string: urlString, encodingInvalidCharacters: false),
				url.isValid
			else {
				showMessage(String(localized: "Invalid URL for the “add” command."))
				return
			}

			WebsitesController.shared.add(url, title: parameters["title"]?.trimmed.nilIfEmpty)
		default:
			// Every other command is one of the actions, named by `Action.urlCommand`. "add" stays here
			// because it is the only one that reads a parameter.
			guard let action = Action.forURLCommand(command) else {
				showMessage("The command “\(command)” is not supported.")
				return
			}

			action.run()
		}
	}
}
