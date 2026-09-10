import type { LocaleMessages } from "../types/i18n.ts";

export const pt = {
  meta: { title: "Reviravolta", description: "Gire o labirinto e conquiste a bola que o adversário já considerava sua." },
  sound: { label: "Som", enable: "Ativar som", disable: "Desativar som" },
  tagline: { first: "Gire o labirinto e conquiste a bola", second: "que o adversário já considerava sua." },
  menu: { friend: "Jogar com um amigo", online: "Adversário aleatório", training: "Treino", how: "Como jogar" },
  rules: {
    board: "O tabuleiro tem nove plataformas giratórias (3×3).", goal: "Recolha o máximo de bolas possível no seu recetor.", turn: "Pode girar uma plataforma por turno.",
    spawn: "Novas bolas surgem de duas células marcadas no centro.", combine: "Após a espera, a jogada do adversário é revelada e as rotações são combinadas.",
    cooldown: "A plataforma girada fica bloqueada no turno seguinte.",
},
  player: { you: "Jogador", opponent: "Adversário", bot: "Bot" },
  name: { label: "O seu nome", online: "Jogadores online:", difficulty: "Dificuldade do bot", easy: "Fácil", medium: "Médio", hard: "Difícil", code: "código", or: "ou" },
  dialog: {
    createTitle: "Jogar com um amigo", createSubmit: "Criar sala", joinTitle: "Entrar no jogo", joinSubmit: "Entrar",
    onlineTitle: "Adversário aleatório", onlineSubmit: "Ligar", trainingTitle: "Treino", trainingSubmit: "Iniciar treino",
},
  action: { connect: "Ligar", join: "Entrar", cancel: "Cancelar", copy: "Copiar link", rematch: "Desforra", newGame: "Novo jogo" },
  lobby: { created: "Sala criada", waiting: "À espera de um adversário…" },
  training: { humanInvite: "Quer jogar com uma pessoa?", exit: "Sair do treino" },
  status: {
    round: "Ronda {round} de {total}", peerFound: "Adversário encontrado, a estabelecer ligação…", storageUnavailable: "O navegador não permite guardar o jogo. Não feche este separador.",
    startupFailed: "Não foi possível iniciar o jogo. Atualize a página nos dois dispositivos.", peerDisconnected: "O adversário desligou-se", waitingOpponent: "À espera do adversário…",
    finding: "A procurar adversário…", queued: "Está na fila. A procurar adversário…", queueRetry: "A ligação à fila foi interrompida. A tentar novamente…",
    queueFailed: "Não foi possível entrar na fila. Tente novamente.", connecting: "A ligar…", copied: "Link copiado para a área de transferência", copyManual: "Copie o link manualmente",
},
  error: {
    matchConnect: "Não foi possível ligar ao adversário encontrado.", createRoom: "Não foi possível criar a sala.", notFound: "Sala não encontrada ou convite expirado. Peça um novo link.",
    oldVersion: "O jogo foi criado numa versão anterior. Atualize os dois dispositivos e crie uma nova sala.", occupied: "O lugar está ocupado. Volte ao separador original do jogo.",
    connectFailed: "Não foi possível ligar. Atualize a página para tentar novamente.", peerAbsent: "Jogo terminado: o adversário esteve ausente por mais de 30 minutos.",
    restoreMismatch: "Não foi possível conciliar o jogo guardado.", platformCooldown: "A plataforma está a arrefecer", nameRequired: "Introduza o seu nome",
},
  result: { win: "Vitória", loss: "Derrota", draw: "Empate" },
} as const satisfies LocaleMessages;
