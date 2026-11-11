# Klawiatura iPhone by MM

Polska klawiatura systemowa na iPhone'a i iPada, wzorowana na Microsoft SwiftKey.

## Funkcje

- **Podpowiedzi słów** — słownik bazowy ok. 50 tys. polskich słów z częstością; dopasowanie ignoruje polskie znaki (`zolw` → `żółw`), poprawia pojedyncze literówki.
- **Nauka słów** — klawiatura zapamiętuje wpisywane słowa; słowo w cudzysłowie na pasku = nieznane, dotknięcie dodaje je do słownika. Podpowiada też następne słowo na podstawie Twoich wcześniejszych par słów.
- **Usuwanie z podpowiedzi** — przytrzymaj podpowiedź → „Usuń”. Listą zablokowanych zarządzasz też w aplikacji.
- **Kopia w iCloud** — nauczone i zablokowane słowa trafiają do prywatnej bazy CloudKit; po zmianie telefonu wracają po zalogowaniu tym samym Apple ID.
- **iPhone i iPad** — jeden układ skalowany do szerokości ekranu, obie orientacje.
- **Dyktowanie po polsku** — klawisz mikrofonu w prawym dolnym rogu (patrz ograniczenie niżej).
- Polskie znaki i cyfry pod przytrzymaniem litery, autokorekta polskich znaków po spacji (cofana Backspace'em), podwójna spacja = kropka, Caps Lock, tryb ciemny.

## Ograniczenie iOS: mikrofon

iOS nie daje rozszerzeniom klawiatur dostępu do mikrofonu. Dlatego klawisz mikrofonu otwiera aplikację Klawiatura MM, która dyktuje systemowym silnikiem mowy (Speech, `pl-PL`). Po „Wstaw do klawiatury” wracasz do poprzedniej aplikacji (‹ w lewym górnym rogu), a klawiatura sama wstawia tekst.

## Budowanie

Wymagania: Mac z Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), konto Apple Developer.

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open KlawiaturaMM.xcodeproj
```

W Xcode, dla obu targetów (`KlawiaturaMM` i `KlawiaturaMMKeyboard`), w zakładce *Signing & Capabilities* wybierz swój zespół. Jeśli identyfikatory `pl.mm.klawiatura`, `group.pl.mm.klawiatura` lub `iCloud.pl.mm.klawiatura` są zajęte, zmień je w `project.yml` i w `Shared/AppGroup.swift`.

Na telefonie: Ustawienia › Ogólne › Klawiatura › Klawiatury › Dodaj klawiaturę › Klawiatura MM, potem włącz **Pełny dostęp** (potrzebny do zapisu słów we wspólnym kontenerze i do dyktowania).

## Architektura

| Katalog | Zawartość |
|---|---|
| `Shared/` | Kod wspólny: `Predictor` (silnik podpowiedzi), `DictionaryStore` (słownik użytkownika jako JSON w App Group), słownik bazowy |
| `Keyboard/` | Rozszerzenie klawiatury (UIKit): układ, pasek podpowiedzi, logika wpisywania |
| `App/` | Aplikacja (SwiftUI): instrukcja, listy słów, dyktowanie, synchronizacja CloudKit |

Przepływ danych: klawiatura zapisuje słowa do pliku w App Group → aplikacja przy każdym otwarciu scala plik z rekordem w CloudKit. Każdy wpis ma znacznik czasu i flagę usunięcia, więc scalanie z kilku urządzeń jest bezkonfliktowe (wygrywa nowszy wpis).

## Słownik bazowy

`Shared/Resources/pl_words.txt` pochodzi z projektu [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (lista `pl_50k`, na podstawie OpenSubtitles 2018), treść na licencji CC BY-SA 4.0.
