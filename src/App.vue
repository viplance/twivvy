<script setup lang="ts">
import { nextTick, onMounted } from "vue";
import { init } from "./game";

onMounted(async () => {
  await nextTick();
  init();
});
</script>

<template>
  <canvas id="scene"></canvas>

  <button
    id="sound-toggle"
    type="button"
    :aria-label="$t('sound.label')"
    aria-pressed="false"
    :title="$t('sound.enable')"
  >
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M11 5 6 9H3v6h3l5 4Z" />
      <path class="sound-off" d="m16 9 6 6m0-6-6 6" />
      <path class="sound-on" d="M15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14" />
    </svg>
  </button>

  <div id="hud" class="hidden">
    <div class="timer-row">
      <div class="timer-bar"><div id="timer-fill"></div></div>
    </div>
    <p id="pause-status" class="hidden" role="status" aria-live="polite">
      {{ $t('status.peerDisconnected') }}
    </p>
  </div>

  <div id="round-title" class="round-title hidden" role="status" aria-live="polite"></div>
  <div id="player-labels" class="player-labels hidden" aria-live="polite">
    <div id="opponent-name" class="receiver-name opponent-name">{{ $t('player.opponent') }}</div>
    <div id="own-name" class="receiver-name own-name">{{ $t('player.you') }}</div>
  </div>

  <main id="menu" class="panel">
    <h1>{{ $t('meta.title') }}</h1>
    <p class="tagline">
      {{ $t('tagline.first') }}<br />{{ $t('tagline.second') }}
    </p>

    <button id="create" class="primary">{{ $t('menu.friend') }}</button>
    <button id="play-online">{{ $t('menu.online') }}</button>
    <button id="training">{{ $t('menu.training') }}</button>

    <details class="rules">
      <summary>{{ $t('menu.how') }}</summary>
      <ul>
        <li>{{ $t('rules.board') }}</li>
        <li>{{ $t('rules.goal') }}</li>
        <li>{{ $t('rules.turn') }}</li>
        <li>{{ $t('rules.spawn') }}</li>
        <li>{{ $t('rules.combine') }}</li>
        <li>{{ $t('rules.cooldown') }}</li>
      </ul>
    </details>
  </main>

  <div id="name-modal" class="modal-backdrop hidden" role="presentation">
    <form
      id="name-form"
      class="panel modal"
      aria-modal="true"
      aria-labelledby="name-title"
      role="dialog"
    >
      <h2 id="name-title">{{ $t('dialog.onlineTitle') }}</h2>
      <label class="name-field" for="player-name">
        <span>{{ $t('name.label') }}</span>
        <input
          id="player-name"
          maxlength="24"
          autocomplete="nickname"
          enterkeyhint="done"
          required
        />
      </label>
      <p id="online-count" class="online-count hidden" aria-live="polite">
        {{ $t('name.online') }} <strong>0</strong>
      </p>
      <p id="matchmaking-status" class="hint hidden" aria-live="polite"></p>
      <fieldset id="training-difficulty" class="difficulty hidden">
        <legend>{{ $t('name.difficulty') }}</legend>
        <label><input type="radio" name="difficulty" value="easy" />{{ $t('name.easy') }}</label>
        <label><input type="radio" name="difficulty" value="medium" checked />{{ $t('name.medium') }}</label>
        <label><input type="radio" name="difficulty" value="hard" />{{ $t('name.hard') }}</label>
      </fieldset>
      <button id="name-submit" class="primary" type="submit">{{ $t('action.connect') }}</button>
      <div id="join-block" class="hidden">
        <div class="divider"><span>{{ $t('name.or') }}</span></div>
        <div class="join-row">
          <input
            id="join-code"
            maxlength="8"
            :placeholder="$t('name.code')"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
          />
          <button id="join" type="button">{{ $t('action.join') }}</button>
        </div>
      </div>
      <button id="name-cancel" class="ghost" type="button">{{ $t('action.cancel') }}</button>
    </form>
  </div>

  <section id="lobby" class="panel hidden">
    <h2>{{ $t('lobby.created') }}</h2>
    <div id="invite-code" class="code">—</div>
    <p id="lobby-hint" class="hint">{{ $t('lobby.waiting') }}</p>
    <button id="copy-link" class="primary">{{ $t('action.copy') }}</button>
    <button id="cancel" class="ghost">{{ $t('action.cancel') }}</button>
  </section>

  <section id="over" class="panel hidden">
    <h2 id="over-title">{{ $t('result.win') }}</h2>
    <div id="over-score" class="code">0 : 0</div>
    <button id="again" class="primary">{{ $t('action.rematch') }}</button>
    <button id="to-menu" class="ghost">{{ $t('action.newGame') }}</button>
  </section>

  <div id="toast" class="hidden"></div>
  <div id="training-controls" class="training-controls hidden">
    <button id="human-invite" class="hidden" type="button">
      {{ $t('training.humanInvite') }}
    </button>
    <button id="exit-training" type="button">{{ $t('training.exit') }}</button>
  </div>
</template>
