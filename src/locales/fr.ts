import type { LocaleMessages } from "../types/i18n.ts";

export const fr = {
  meta: { title: "Rotation", description: "Faites tourner le labyrinthe et prenez la bille que votre adversaire croyait déjà sienne." },
  sound: { label: "Son", enable: "Activer le son", disable: "Couper le son" },
  tagline: { first: "Faites tourner le labyrinthe et prenez la bille", second: "que votre adversaire croyait déjà sienne." },
  menu: { friend: "Jouer avec un ami", online: "Adversaire aléatoire", training: "Entraînement", how: "Comment jouer" },
  rules: {
    board: "Le plateau comporte neuf plateformes rotatives (3×3).", goal: "Récupérez autant de billes que possible dans votre récepteur.", turn: "Vous pouvez faire tourner une plateforme par tour.",
    spawn: "De nouvelles billes apparaissent dans deux cases marquées au centre.", combine: "Après l'attente, le coup adverse est révélé et les rotations se combinent.",
    cooldown: "La plateforme tournée est bloquée pendant le tour suivant.",
},
  player: { you: "Joueur", opponent: "Adversaire", bot: "Bot" },
  name: { label: "Votre nom", online: "Joueurs en ligne :", difficulty: "Difficulté du bot", easy: "Facile", medium: "Moyen", hard: "Difficile", code: "code", or: "ou" },
  dialog: {
    createTitle: "Jouer avec un ami", createSubmit: "Créer une salle", joinTitle: "Rejoindre la partie", joinSubmit: "Rejoindre",
    onlineTitle: "Adversaire aléatoire", onlineSubmit: "Connexion", trainingTitle: "Entraînement", trainingSubmit: "Commencer l'entraînement",
},
  action: { connect: "Connexion", join: "Rejoindre", cancel: "Annuler", copy: "Copier le lien", rematch: "Revanche", newGame: "Nouvelle partie" },
  lobby: { created: "Salle créée", waiting: "En attente d'un adversaire…" },
  training: { humanInvite: "Voulez-vous jouer avec une personne ?", exit: "Quitter l'entraînement" },
  status: {
    round: "Manche {round} sur {total}", peerFound: "Adversaire trouvé, connexion en cours…", storageUnavailable: "Le navigateur ne permet pas d'enregistrer la partie. Ne fermez pas cet onglet.",
    startupFailed: "Impossible de démarrer la partie. Actualisez la page sur les deux appareils.", peerDisconnected: "L'adversaire s'est déconnecté", waitingOpponent: "En attente de l'adversaire…",
    finding: "Recherche d'un adversaire…", queued: "Vous êtes dans la file. Recherche d'un adversaire…", queueRetry: "Connexion à la file interrompue. Nouvelle tentative…",
    queueFailed: "Impossible de rejoindre la file. Réessayez.", connecting: "Connexion…", copied: "Lien copié dans le presse-papiers", copyManual: "Copiez le lien manuellement",
},
  error: {
    matchConnect: "Impossible de se connecter à l'adversaire trouvé.", createRoom: "Impossible de créer la salle.", notFound: "Salle introuvable ou invitation expirée. Demandez un nouveau lien.",
    oldVersion: "La partie a été créée avec une ancienne version. Actualisez les deux appareils et créez une nouvelle salle.", occupied: "La place est occupée. Revenez à l'onglet d'origine de la partie.",
    connectFailed: "Connexion impossible. Actualisez la page pour réessayer.", peerAbsent: "Partie terminée : l'adversaire était absent depuis plus de 30 minutes.",
    restoreMismatch: "Impossible de réconcilier la partie enregistrée.", platformCooldown: "La plateforme est en refroidissement", nameRequired: "Saisissez votre nom",
},
  result: { win: "Victoire", loss: "Défaite", draw: "Match nul" },
} as const satisfies LocaleMessages;
