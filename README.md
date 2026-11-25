# språk

A flashcard study app for macOS, built with Flutter. Make decks of cards for
vocabulary, math or anything else, then study them in small groups with
multiple choice, typing or flash cards. You can also turn on AI help that
fills in cards, grades your answers and talks with you as a tutor.

## Running the app

### Requirements

- macOS (this is the only platform set up in the project)
- [Flutter](https://docs.flutter.dev/get-started/install/macos) with Dart SDK 3.11 or newer
- Xcode and CocoaPods, which Flutter needs to build macOS apps

Run `flutter doctor` to check your setup.

### Run in development

```sh
flutter pub get
flutter run -d macos
```

### Build a release app

```sh
flutter build macos
open build/macos/Build/Products/Release/sprak.app
```

### Run the tests

```sh
flutter test
```

## Setting up AI (optional)

The AI features are optional. Without them, the app still works as a normal
flashcard app. To turn them on, open **Settings** (the gear icon on the home
screen), choose a provider, and enter an API key:

| Provider | Default model | Notes |
|---|---|---|
| Anthropic (Claude) | `claude-opus-4-8` | Can also read the key from the `ANTHROPIC_API_KEY` environment variable |
| OpenAI | `gpt-4o` | |
| Google Gemini | `gemini-2.0-flash` | |
| Custom (OpenAI-compatible) | `llama3.1` | Any OpenAI-compatible endpoint, such as Ollama, LM Studio, OpenRouter or Groq. Defaults to `http://localhost:11434/v1`, and no key is needed |

Settings can also fetch the provider's list of models so you can pick a
different one.

## Features

### Decks and folders
- The app calls decks **sets**. A set can be one of three kinds:
  - **Language**: pick a native language and a target language. 20 languages
    are supported, including Spanish, Russian, Japanese, Swedish and Arabic.
  - **Math**: pairs a prompt with an answer, and renders inline LaTeX
    (`$\frac{a}{b}$`).
  - **General**: pairs any question with an answer.
- You can group sets into folders on the home screen, and rename, move or
  delete them.

### Adding and editing cards
- Type one side of a card and the AI fills in the other side after a short
  pause. For language sets it also suggests the dictionary form of an
  inflected word, such as an infinitive.
- **Tags** (for example "verb" or "chapter 3"): the AI suggests tags for new
  cards, and you can manage a set's tags and filter its cards by tag.
- **Notes**: a card can have a free-form note, such as an example sentence
  or a memory trick. The note is shown during review but you are never asked
  to answer it.
- **Edit with AI**: describe a change in plain words, such as "add 20 common
  kitchen words" or "tag all the verbs". The AI proposes cards to add,
  remove, retag or re-note, and you review the list before anything is
  applied.
- Search the cards in a set, and sort them by when they were added or by how
  often you missed them.

### Studying
When you click **Learn** on a set, it asks you a few questions:
- **What to study**: the whole set, one card group, cards with certain tags,
  pick up a saved session, or focus on the cards you miss most.
- **How to answer**:
  - *Multiple choice*: pick the right answer out of several options.
  - *Typing*: type the answer.
  - *Both*: each card must be answered by multiple choice and by typing.
  - *Flash card*: flip the card and say whether you knew it.
- **Direction**: front → back, back → front, or both.
- **Grading** for typed answers: *exact match*, or *AI grading*, which
  accepts equivalent answers such as synonyms or small spelling differences.
  If exact match marks you wrong, you can choose "My answer was right — count
  it."

Cards are shuffled into small groups (you choose how many per group). You
clear one group before moving to the next. Other study features:
- **Strict mode** (lock icon): one miss restarts the group.
- **Read aloud** (speaker icon, language sets): words are read aloud with
  your system's text-to-speech voice for that language.
- **Tutor chat**: ask the AI about the current card while you study. You can
  dock and resize the chat panel.
- **Keyboard indicator**: shows which macOS keyboard layout is active, which
  helps when you type in another alphabet.
- If you quit in the middle of studying, your session is saved so you can
  continue later.

### Keyboard shortcuts while studying
| Mode | Keys |
|---|---|
| Multiple choice | `1`–`8` pick an answer, `Enter` goes to the next card |
| Typing | `Enter` checks the answer, then goes to the next card |
| Flash card | `Space`/`Enter` flips the card, `1`/`←` means didn't know, `2`/`→` means knew it |
| End of a group | `Enter` starts the next group |

### Progress tracking
Every first try at a card is recorded. Each card gets a mastery level:
- **New**: never studied.
- **Learning**: fewer than three perfect sessions in a row.
- **Strong**: on a streak and reviewed recently.
- **Fading**: was strong, but hasn't been reviewed in 14 or more days.

Each set shows a retention summary on the home screen.

### Appearance
Switch between two looks in Settings: **Aurora** (dark blue with mint and
violet) and **Hacker** (a green terminal look with scanlines).

## Where data is stored

All sets, folders and progress are saved in one JSON file, `decks.json`, in
the app's Application Support folder:

```
~/Library/Containers/com.sprak.sprak/Data/Library/Application Support/com.sprak.sprak/decks.json
```

Settings and API keys are kept separately in the app's preferences
(`shared_preferences`).

## Project layout

```
lib/
  main.dart            app entry point
  models.dart          decks, cards, reviews, quiz settings
  storage.dart         loading and saving decks.json
  theme.dart           Aurora and Hacker looks
  screens/             home, set detail, study, settings
  services/            LLM providers, text-to-speech, keyboard layout
  widgets/             dialogs, tag chips, chat, LaTeX text
macos/                 macOS runner (includes the native keyboard-layout channel)
test/                  widget and unit tests
```
