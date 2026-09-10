import type { LocaleMessages } from "../types/i18n.ts";

export const es = {
  meta: { title: "Giro", description: "Gira el laberinto y consigue la bola que tu rival ya creía suya." },
  sound: { label: "Sonido", enable: "Activar sonido", disable: "Desactivar sonido" },
  tagline: { first: "Gira el laberinto y consigue la bola", second: "que tu rival ya creía suya." },
  menu: { friend: "Jugar con un amigo", online: "Rival aleatorio", training: "Entrenamiento", how: "Cómo jugar" },
  rules: {
    board: "El tablero tiene nueve plataformas giratorias (3×3).", goal: "Recoge tantas bolas como puedas en tu receptor.",
    turn: "Puedes girar una plataforma por turno.", spawn: "Las bolas nuevas aparecen en dos casillas marcadas del centro.",
    combine: "Tras la espera se revela la jugada del rival y los giros se combinan.", cooldown: "La plataforma girada queda bloqueada durante el siguiente turno.",
},
  player: { you: "Jugador", opponent: "Rival", bot: "Bot" },
  name: { label: "Tu nombre", online: "Jugadores en línea:", difficulty: "Dificultad del bot", easy: "Fácil", medium: "Media", hard: "Difícil", code: "código", or: "o" },
  dialog: {
    createTitle: "Jugar con un amigo", createSubmit: "Crear sala", joinTitle: "Unirse a la partida", joinSubmit: "Entrar",
    onlineTitle: "Rival aleatorio", onlineSubmit: "Conectar", trainingTitle: "Entrenamiento", trainingSubmit: "Iniciar entrenamiento",
},
  action: { connect: "Conectar", join: "Entrar", cancel: "Cancelar", copy: "Copiar enlace", rematch: "Revancha", newGame: "Nueva partida" },
  lobby: { created: "Sala creada", waiting: "Esperando a un rival…" },
  training: { humanInvite: "¿Quieres jugar con una persona?", exit: "Salir del entrenamiento" },
  status: {
    round: "Ronda {round} de {total}", peerFound: "Rival encontrado, estableciendo conexión…",
    storageUnavailable: "El navegador no permite guardar la partida. No cierres esta pestaña.", startupFailed: "No se pudo iniciar la partida. Actualiza la página en ambos dispositivos.",
    peerDisconnected: "El rival se desconectó", waitingOpponent: "Esperando al rival…", finding: "Buscando rival…", queued: "Estás en la cola. Buscando rival…",
    queueRetry: "Se perdió la conexión con la cola. Reintentando…", queueFailed: "No se pudo entrar en la cola. Inténtalo de nuevo.",
    connecting: "Conectando…", copied: "Enlace copiado al portapapeles", copyManual: "Copia el enlace manualmente",
},
  error: {
    matchConnect: "No se pudo conectar con el rival encontrado.", createRoom: "No se pudo crear la sala.", notFound: "No se encontró la sala o la invitación caducó. Pide un enlace nuevo.",
    oldVersion: "La partida se creó con una versión anterior. Actualiza ambos dispositivos y crea una sala nueva.", occupied: "La plaza está ocupada. Vuelve a la pestaña original de la partida.",
    connectFailed: "No se pudo conectar. Actualiza la página para intentarlo de nuevo.", peerAbsent: "Partida terminada: el rival estuvo ausente más de 30 minutos.",
    restoreMismatch: "No se pudo conciliar la partida guardada.", platformCooldown: "La plataforma se está enfriando", nameRequired: "Introduce tu nombre",
},
  result: { win: "Victoria", loss: "Derrota", draw: "Empate" },
} as const satisfies LocaleMessages;
