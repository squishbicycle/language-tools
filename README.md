# language-tools

Offline command-line tools and menu-bar apps for learning **Japanese** and **Spanish** on macOS. No accounts, no ads, no subscriptions.

| Tool | What it does |
|---|---|
| **jdict** | Japanese ↔ English dictionary that understands conjugations (`食べました` → 食べる), plus a hotkey pop-up (⌃⌥K) |
| **jsay** | Plays a native speaker saying a Japanese word |
| **jsent** | Reads a Japanese sentence aloud, slowly |
| **sdict** | Spanish ↔ English dictionary that understands conjugations (`hay` → haber), with word-by-word sentence breakdowns, plus a hotkey pop-up (⌃⌥S) that translates whole sentences on-device |
| **ssay** | Says Spanish words or sentences in a natural Latin American voice |

The tools are Python 3 scripts using only the standard library; the pop-ups are small SwiftUI apps.

## Install

Needs macOS 14+ (26+ for sentence translation), Python 3.9+, and the Xcode Command Line Tools.

```sh
git clone https://github.com/squishbicycle/language-tools.git ~/code/language-tools
ln -s ~/code/language-tools/japanese ~/japanese-tools
ln -s ~/code/language-tools/spanish ~/spanish-tools

mkdir -p ~/.local/bin          # must be on your PATH
for t in jdict jsay jsent; do ln -s ~/japanese-tools/$t ~/.local/bin/$t; done
for t in sdict ssay; do ln -s ~/spanish-tools/$t ~/.local/bin/$t; done

jdict --update && sdict --update      # download and build the dictionaries
~/japanese-tools/jdict-app/build.sh   # installs ~/Applications/JDict.app
~/spanish-tools/sdict-app/build.sh    # installs ~/Applications/SDict.app
```

## Natural voices (optional)

jsent, ssay and jsay's fallback can use Google Cloud Text-to-Speech; without it they use Tatoeba recordings and the macOS voices. Clips are cached, so each sentence is paid for once ([pricing](https://cloud.google.com/text-to-speech/pricing)).

1. In a Google Cloud project with billing, enable the **Cloud Text-to-Speech API**.
2. Create an API key and restrict it to that API.
3. Save it: `pbpaste > ~/japanese-tools/google-tts-key && chmod 600 ~/japanese-tools/google-tts-key` (it's gitignored).
4. Set a budget with alerts. [`japanese/stop-billing/`](japanese/stop-billing/) can also cut billing off automatically when the budget is exceeded.

## Credits

Dictionary data is downloaded on your machine, not included here.

- [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) © EDRDG, [CC BY-SA 4.0](https://www.edrdg.org/edrdg/licence.html), via [jmdict-simplified](https://github.com/scriptin/jmdict-simplified)
- [Wiktionary](https://en.wiktionary.org/), [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), via [kaikki.org](https://kaikki.org/)
- [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit Dave, CC BY-SA 4.0
- [Tatoeba](https://tatoeba.org/en/terms_of_use) sentences and recordings, CC BY 2.0 FR
- Readings from [Jisho](https://jisho.org/); word audio streamed from JapanesePod101 (not redistributed)

See the [changelog](CHANGELOG.md) for what's new.

## License

[GPL v3](LICENSE) or later. (Versions downloaded before 2026-11-22 were MIT-licensed.)
