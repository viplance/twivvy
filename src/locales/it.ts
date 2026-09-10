import type { LocaleMessages } from "../types/i18n.ts";

export const it = {
  meta: { title: "Giravolta", description: "Ruota il labirinto e conquista la pallina che l'avversario credeva già sua." },
  sound: { label: "Audio", enable: "Attiva audio", disable: "Disattiva audio" },
  tagline: { first: "Ruota il labirinto e conquista la pallina", second: "che l'avversario credeva già sua." },
  menu: { friend: "Gioca con un amico", online: "Avversario casuale", training: "Allenamento", how: "Come si gioca" },
  rules: {
    board: "Il campo ha nove piattaforme girevoli (3×3).", goal: "Raccogli più palline possibile nel tuo ricevitore.", turn: "Puoi ruotare una piattaforma per turno.",
    spawn: "Le nuove palline appaiono da due caselle segnate al centro.", combine: "Dopo l'attesa viene rivelata la mossa avversaria e le rotazioni si combinano.",
    cooldown: "La piattaforma ruotata resta bloccata per il turno successivo.",
},
  player: { you: "Giocatore", opponent: "Avversario", bot: "Bot" },
  name: { label: "Il tuo nome", online: "Giocatori online:", difficulty: "Difficoltà del bot", easy: "Facile", medium: "Media", hard: "Difficile", code: "codice", or: "oppure" },
  dialog: {
    createTitle: "Gioca con un amico", createSubmit: "Crea stanza", joinTitle: "Entra nella partita", joinSubmit: "Entra",
    onlineTitle: "Avversario casuale", onlineSubmit: "Connetti", trainingTitle: "Allenamento", trainingSubmit: "Inizia allenamento",
},
  action: { connect: "Connetti", join: "Entra", cancel: "Annulla", copy: "Copia link", rematch: "Rivincita", newGame: "Nuova partita" },
  lobby: { created: "Stanza creata", waiting: "In attesa di un avversario…" },
  training: { humanInvite: "Vuoi giocare con una persona?", exit: "Esci dall'allenamento" },
  status: {
    round: "Round {round} di {total}", peerFound: "Avversario trovato, connessione in corso…", storageUnavailable: "Il browser non consente di salvare la partita. Non chiudere questa scheda.",
    startupFailed: "Impossibile avviare la partita. Aggiorna la pagina su entrambi i dispositivi.", peerDisconnected: "L'avversario si è disconnesso", waitingOpponent: "In attesa dell'avversario…",
    finding: "Ricerca avversario…", queued: "Sei in coda. Ricerca avversario…", queueRetry: "Connessione alla coda interrotta. Nuovo tentativo…",
    queueFailed: "Impossibile entrare in coda. Riprova.", connecting: "Connessione…", copied: "Link copiato negli appunti", copyManual: "Copia il link manualmente",
},
  error: {
    matchConnect: "Impossibile connettersi all'avversario trovato.", createRoom: "Impossibile creare la stanza.", notFound: "Stanza non trovata o invito scaduto. Richiedi un nuovo link.",
    oldVersion: "La partita è stata creata con una versione precedente. Aggiorna entrambi i dispositivi e crea una nuova stanza.", occupied: "Il posto è occupato. Torna alla scheda originale della partita.",
    connectFailed: "Connessione non riuscita. Aggiorna la pagina per riprovare.", peerAbsent: "Partita terminata: l'avversario è rimasto assente per più di 30 minuti.",
    restoreMismatch: "Impossibile riconciliare la partita salvata.", platformCooldown: "La piattaforma è in raffreddamento", nameRequired: "Inserisci il tuo nome",
},
  result: { win: "Vittoria", loss: "Sconfitta", draw: "Pareggio" },
} as const satisfies LocaleMessages;
