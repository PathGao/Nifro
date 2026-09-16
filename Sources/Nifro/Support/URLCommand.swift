import Foundation

/**
Which command a `nifro:` URL is asking for.

Two spellings arrive and they parse differently. `nifro:reload` is the documented one, and it puts the
word in the path. `nifro://reload` is the one people write, because every other URL they have ever
typed has the slashes, and it puts the word in the *host* with the path left empty.

Reading only the path answered the second spelling with "The command “” is not supported" — a message
naming nothing, and the same message a genuine typo gets, so there was no way to tell "you wrote the
slashes" apart from "there is no such command". The command simply did not run, and the alert said so
in a way that pointed at the wrong thing.

Both are accepted rather than one being declared correct. A URL scheme is a public interface; scripts
that other people have already written contain whichever spelling they guessed, and breaking those to
win an argument about slashes is not worth anything.
*/
func urlCommand(from components: URLComponents) -> String {
	if let host = components.host, !host.isEmpty {
		return host
	}

	// `nifro:///reload` is a third way to write it, and it lands here with a leading slash.
	return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}
