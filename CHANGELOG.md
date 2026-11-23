# Changelog

What changed in each update, newest first.

## 2026-11-22

- **License changed from MIT to GPL v3 or later.**

### sdict
- **Accentless "por que" now gives "why."** Typing *por que* (or *¿por que?*) shows *por qué* ("why") first, then *porque* ("because") and *porqué* ("the reason"). Before, it showed a pile of "misspelling of…" stubs with "because" on top. When a typo could be one of several words, the one that differs only by a missing accent comes first.
- **Set phrases are looked up whole.** *por qué*, *de nada*, *muy bien* and other dictionary phrases now show their own entry instead of being split into a word-by-word breakdown.
- Wiktionary's empty "see *por*, *que*" phrase entries are hidden.
- **Better short meanings in word-by-word breakdowns.** Shortened forms now show what they mean: *muy* → "very" (before, it showed the meaning of *mucho*).

## 2026-11-20

### Spanish
- **SDict.app translates whole sentences** with Apple's on-device Translation framework, both ways (type `en` first for English → Spanish). Nothing is sent to a server. Needs macOS 26 or later.
- **Word-by-word breakdowns** for sentences, with each word traced to its dictionary form and grammar (*hay → haber: there is, there are (present, él/ella/usted)*). In the app, click any word to open its entry.
- **New hotkey ⌃⌥⇧S** opens an empty search window.
- **New tool: ssay** says Spanish words and sentences aloud with Google's Chirp 3 HD Latin American voices, cached, falling back to the macOS voice.
- sdict ranks common words first using a word-frequency list (*tiendas* → *tienda*, not the rare verb *tender*).
- Words that are barely Spanish show the English → Spanish result first (*hot* → *caliente*).

### Japanese
- Quick start and a step-by-step Google Cloud Text-to-Speech setup guide in the README.
- **stop-billing:** an optional Cloud Function that unlinks billing when a budget is exceeded.

### First release
- **jdict** and JDict.app: offline Japanese ↔ English dictionary with conjugation lookup.
- **jsay**: native-speaker recordings of Japanese words.
- **jsent**: slow, natural Japanese sentence audio.
- **sdict** and SDict.app: offline Spanish ↔ English dictionary that understands conjugated verbs.
