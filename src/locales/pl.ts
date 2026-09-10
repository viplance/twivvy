import type { LocaleMessages } from "../types/i18n.ts";

export const pl = {
  meta: { title: "Zakręt", description: "Obróć labirynt i zdobądź kulkę, którą przeciwnik uważał już za swoją." },
  sound: { label: "Dźwięk", enable: "Włącz dźwięk", disable: "Wyłącz dźwięk" },
  tagline: { first: "Obróć labirynt i zdobądź kulkę,", second: "którą przeciwnik uważał już za swoją." },
  menu: { friend: "Zagraj ze znajomym", online: "Losowy przeciwnik", training: "Trening", how: "Jak grać" },
  rules: {
    board: "Plansza składa się z dziewięciu obrotowych platform (3×3).", goal: "Zbierz jak najwięcej kulek w swoim odbiorniku.", turn: "W każdej turze możesz obrócić jedną platformę.",
    spawn: "Nowe kulki pojawiają się w dwóch oznaczonych polach pośrodku.", combine: "Po odczekaniu ruch przeciwnika zostaje ujawniony, a obroty się łączą.",
    cooldown: "Obrócona platforma jest zablokowana w następnej turze.",
},
  player: { you: "Gracz", opponent: "Przeciwnik", bot: "Bot" },
  name: { label: "Twoja nazwa", online: "Gracze online:", difficulty: "Poziom bota", easy: "Łatwy", medium: "Średni", hard: "Trudny", code: "kod", or: "lub" },
  dialog: {
    createTitle: "Zagraj ze znajomym", createSubmit: "Utwórz pokój", joinTitle: "Dołącz do gry", joinSubmit: "Dołącz",
    onlineTitle: "Losowy przeciwnik", onlineSubmit: "Połącz", trainingTitle: "Trening", trainingSubmit: "Rozpocznij trening",
},
  action: { connect: "Połącz", join: "Dołącz", cancel: "Anuluj", copy: "Kopiuj link", rematch: "Rewanż", newGame: "Nowa gra" },
  lobby: { created: "Pokój utworzony", waiting: "Oczekiwanie na przeciwnika…" },
  training: { humanInvite: "Chcesz zagrać z człowiekiem?", exit: "Zakończ trening" },
  status: {
    round: "Runda {round} z {total}", peerFound: "Znaleziono przeciwnika, nawiązywanie połączenia…", storageUnavailable: "Przeglądarka nie pozwala zapisać gry. Nie zamykaj tej karty.",
    startupFailed: "Nie udało się uruchomić gry. Odśwież stronę na obu urządzeniach.", peerDisconnected: "Przeciwnik się rozłączył", waitingOpponent: "Oczekiwanie na przeciwnika…",
    finding: "Szukanie przeciwnika…", queued: "Jesteś w kolejce. Szukanie przeciwnika…", queueRetry: "Utracono połączenie z kolejką. Ponawianie…",
    queueFailed: "Nie udało się dołączyć do kolejki. Spróbuj ponownie.", connecting: "Łączenie…", copied: "Link skopiowano do schowka", copyManual: "Skopiuj link ręcznie",
},
  error: {
    matchConnect: "Nie udało się połączyć ze znalezionym przeciwnikiem.", createRoom: "Nie udało się utworzyć pokoju.", notFound: "Nie znaleziono pokoju lub zaproszenie wygasło. Poproś o nowy link.",
    oldVersion: "Gra została utworzona w starszej wersji. Odśwież oba urządzenia i utwórz nowy pokój.", occupied: "Miejsce jest zajęte. Wróć do pierwotnej karty gry.",
    connectFailed: "Nie udało się połączyć. Odśwież stronę, aby spróbować ponownie.", peerAbsent: "Gra zakończona: przeciwnik był nieobecny przez ponad 30 minut.",
    restoreMismatch: "Nie udało się uzgodnić zapisanej gry.", platformCooldown: "Platforma się chłodzi", nameRequired: "Wpisz swoją nazwę",
},
  result: { win: "Zwycięstwo", loss: "Porażka", draw: "Remis" },
} as const satisfies LocaleMessages;
