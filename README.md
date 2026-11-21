# language-tools

Small, offline-first command-line tools and menu-bar apps for learning **Japanese** and **Spanish** on macOS. No accounts, no ads, no subscriptions; the dictionaries run entirely on your Mac.

| Tool | Language | What it does |
|---|---|---|
| [**jdict**](#jdict--japanese-dictionary) | Japanese | Offline Japanese ↔ English dictionary with conjugation lookup, plus a hotkey pop-up window |
| [**jsay**](#jsay--hear-a-japanese-word) | Japanese | Plays a native speaker saying a Japanese word |
| [**jsent**](#jsent--hear-a-japanese-sentence) | Japanese | Reads a whole Japanese sentence aloud, slowly |
| [**sdict**](#sdict--spanish-dictionary) | Spanish | Offline Spanish ↔ English dictionary that understands conjugated verbs, plus a hotkey pop-up window |

All four are plain Python 3 scripts that use only the standard library. The two pop-up apps are small SwiftUI programs.

### Quick start

```sh
git clone https://github.com/squishbicycle/language-tools.git ~/code/language-tools
ln -s ~/code/language-tools/japanese ~/japanese-tools
ln -s ~/code/language-tools/spanish ~/spanish-tools
~/spanish-tools/sdict --update && ~/spanish-tools/sdict hay      # → haber: "there is, there are"
~/japanese-tools/jdict --update && ~/japanese-tools/jdict 食べました   # → 食べる: "to eat"
```

Then build the hotkey apps and put the commands on your PATH: see [Install](#install). Japanese sentence audio can optionally use Google's voices: see [Setting up Google voices](#setting-up-google-voices-optional).

---

## jdict — Japanese dictionary

An offline Japanese–English dictionary built on [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html), the same data behind Jisho and Yomitan.

- **Understands conjugations:** `食べたくなかった` → `食べる` (Yomitan-style deinflection), with Genki-style labels (ru-verb / u-verb).
- **Forgiving:** retries big↔small kana typos and matches the longest word at the start of what you typed.
- **Both directions:** `jdict eat` searches English → Japanese.
- **JDict.app:** a menu-bar app (辞). Copy a word, press **⌃⌥K**, and a floating window shows the entry. Each entry has a ▶ button that runs `jsay`.

```sh
jdict 食べました       # conjugated forms are fine
jdict dungeon          # English → Japanese
jdict                  # look up whatever is on the clipboard
jdict --update         # download the latest JMdict and rebuild the database (~95 MB)
```

## jsay — hear a Japanese word

Plays a **real native-speaker recording** of a word: no robotic text-to-speech.

- Looks up the reading on Jisho, then plays the JapanesePod101 recording (the same source Yomitan uses).
- If no recording exists, it falls back to Google's high-quality voice through `jsent --google-only`, clearly labelled as "not a native recording".

```sh
jsay 学生      # a specific word
jsay           # the word on the clipboard
```

Tip: bind `jsay` to a keyboard shortcut with the macOS Shortcuts app (a *Run Shell Script* action) to hear any copied word instantly.

## jsent — hear a Japanese sentence

Reads a whole sentence aloud at a learner-friendly speed. It tries, in order:

1. **Tatoeba**, a real native-speaker recording of that exact sentence, if one exists.
2. **Google Cloud Text-to-Speech** (Chirp 3 HD voices, 0.75× speed by default). Results are cached, so replays are free and instant.
3. **macOS text-to-speech** (Otoya), for example when you're offline.

```sh
jsent 私はアメリカ人です。
jsent -s 0.6 ...        # slower
jsent -g Aoede ...      # a different Google voice
jsent --mac ...         # skip straight to the macOS voice
```

Google voices are optional; without a key, jsent uses Tatoeba and the macOS voice. See [Setting up Google voices](#setting-up-google-voices-optional). `jsay` also uses Google as its fallback when a word has no native recording.

## sdict — Spanish dictionary

An offline Spanish–English dictionary built on [English Wiktionary](https://en.wiktionary.org/) data (via [kaikki.org](https://kaikki.org/dictionary/Spanish/)), made because the macOS Dictionary answers *hay* with "to make hay".

- **Spanish first:** *hay* → *haber* ("there is, there are"), not dried grass.
- **Understands conjugations:** *voy* → *ir*, *tuviera* → *tener*, *frutas* → *fruta*.
- **Accents optional:** *tambien* → *también*. Typos get a "did you mean": *fruitas* → *frutas*.
- **Learner details:** nouns show their article (*la ciudad*), most meanings include an example sentence, and pronunciation follows Latin American Spanish.
- **Common words first:** a word-frequency list puts everyday meanings on top: *tiendas* → *tienda* (store), not a rare form of *tender*.
- **Both directions:** `sdict -e city` → *ciudad*.
- **SDict.app:** a menu-bar app (Ñ). Copy a word, press **⌃⌥S**, and a floating window shows the entry. Type `en city` in the window to search English. The ▶ button speaks the word with the Mexican Spanish voice *Paulina*.

```sh
sdict hay
sdict "yo tambien"
sdict -e city          # English → Spanish
sdict --update         # download the Wiktionary data (~100 MB) + frequency list and build the database
```

---

## Install

Requirements: macOS 14 or later, Python 3.9+ (the system `python3` is fine), and the Xcode Command Line Tools for building the apps (`xcode-select --install`).

The scripts and apps expect to live in `~/japanese-tools` and `~/spanish-tools`:

```sh
git clone https://github.com/squishbicycle/language-tools.git ~/code/language-tools
ln -s ~/code/language-tools/japanese ~/japanese-tools
ln -s ~/code/language-tools/spanish ~/spanish-tools

mkdir -p ~/.local/bin          # make sure ~/.local/bin is on your PATH
for t in jdict jsay jsent; do ln -s ~/japanese-tools/$t ~/.local/bin/$t; done
ln -s ~/spanish-tools/sdict ~/.local/bin/sdict

jdict --update                 # first run: download and build the dictionaries
sdict --update

~/japanese-tools/jdict-app/build.sh   # installs ~/Applications/JDict.app
~/spanish-tools/sdict-app/build.sh    # installs ~/Applications/SDict.app
```

Open each app once, then use its menu-bar icon to turn on **Open at Login** or pick a different hotkey.

## Setting up Google voices (optional)

`jsent` (and `jsay`'s fallback) can use Google Cloud Text-to-Speech's natural-sounding Chirp 3 HD voices. This needs a Google Cloud account with billing turned on. Google's [pricing page](https://cloud.google.com/text-to-speech/pricing) lists the current rates and the monthly free allowance; reading single sentences is usually tiny, and jsent caches every clip, so a sentence is only paid for once.

1. **Create a project** at [console.cloud.google.com](https://console.cloud.google.com/) and link a billing account.
2. **Enable the API:** *APIs & Services → Library →* search **Cloud Text-to-Speech API** → **Enable**.
3. **Create a key:** *APIs & Services → Credentials → Create credentials → API key*.
4. **Restrict the key** (important): edit it, and under *API restrictions* choose **Restrict key → Cloud Text-to-Speech API**. A leaked key then can't be used for anything else.
5. **Save it** next to jsent, readable only by you:
   ```sh
   pbpaste > ~/japanese-tools/google-tts-key     # with the key copied to the clipboard
   chmod 600 ~/japanese-tools/google-tts-key
   ```
   `google-tts-key` is listed in `.gitignore`, so it is never committed. Never paste the key into code, issues, or chat.
6. **Set a budget:** *Billing → Budgets & alerts → Create budget* (for example $1) with email alerts.
7. **Test it:** `jsent 私はアメリカ人です。` should play Google's voice, and `jsent --google-only ...` fails loudly if the key isn't working.

### Optional: automatic billing kill switch

A budget only sends alerts. [`japanese/stop-billing/`](japanese/stop-billing/) contains a small Cloud Function that **unlinks billing from the project** as soon as a budget notification reports spending over the limit, so a runaway bill can't happen. It needs the [gcloud CLI](https://cloud.google.com/sdk/docs/install):

```sh
gcloud auth login
gcloud billing budgets list --billing-account=XXXXXX-XXXXXX-XXXXXX   # copy the budget's name
~/japanese-tools/stop-billing/setup.sh YOUR_PROJECT_ID billingAccounts/XXXXXX-XXXXXX-XXXXXX/budgets/BUDGET_ID
```

Keep in mind that budget notifications can lag real spending by hours, so this caps costs rather than enforcing an exact limit. When it triggers, everything paid in that project stops until you relink billing: `gcloud billing projects link YOUR_PROJECT_ID --billing-account=XXXXXX-XXXXXX-XXXXXX`.

## Data and credits

The dictionary data is downloaded on your machine and is **not** included in this repository.

- **JMdict** © the [Electronic Dictionary Research and Development Group](https://www.edrdg.org/), used under [CC BY-SA 4.0](https://www.edrdg.org/edrdg/licence.html), via [jmdict-simplified](https://github.com/scriptin/jmdict-simplified).
- **Wiktionary** content is available under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); extracted by [Wiktextract / kaikki.org](https://kaikki.org/).
- **Spanish word frequencies** come from [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit Dave (OpenSubtitles 2018), licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
- **Tatoeba** sentences and recordings are licensed under [CC BY 2.0 FR](https://tatoeba.org/en/terms_of_use) and their recorders' individual licenses.
- Word readings come from the [Jisho](https://jisho.org/) API. Word audio is streamed from JapanesePod101's public dictionary endpoint and is not redistributed.

## License

The code in this repository is released under the [MIT License](LICENSE).
