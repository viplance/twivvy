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
    aria-label="Звук"
    aria-pressed="false"
    title="Включить звук"
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
      Соперник отсоединился
    </p>
  </div>

  <div id="round-title" class="round-title hidden" role="status" aria-live="polite"></div>
  <div id="player-labels" class="player-labels hidden" aria-live="polite">
    <div id="opponent-name" class="receiver-name opponent-name">Соперник</div>
    <div id="own-name" class="receiver-name own-name">Игрок</div>
  </div>

  <main id="menu" class="panel">
    <h1>Twivvy</h1>
    <p class="tagline">
      Поверни лабиринт и забери шарик,<br />который соперник уже считал своим.
    </p>

    <button id="create" class="primary">Играть с другом</button>
    <button id="play-online">Случайный соперник</button>
    <button id="training">Тренировка</button>

    <details class="rules">
      <summary>Как играть</summary>
      <ul>
        <li>Поле из девяти поворотных платформ (3x3).</li>
        <li>Цель игры — собрать в свой приёмник как можно больше шариков.</li>
        <li>Игрок может повернуть одну платформу за ход.</li>
        <li>Новые шарики появляются из двух отмеченных клеток в центре поля.</li>
        <li>После ожидания открывается ход соперника — повороты складываются.</li>
        <li>Повёрнутая платформа блокируется на следующий такт.</li>
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
      <h2 id="name-title">Случайный соперник</h2>
      <label class="name-field" for="player-name">
        <span>Ваше имя</span>
        <input
          id="player-name"
          maxlength="24"
          autocomplete="nickname"
          enterkeyhint="done"
          required
        />
      </label>
      <p id="online-count" class="online-count hidden" aria-live="polite">
        Человек в сети: <strong>0</strong>
      </p>
      <p id="matchmaking-status" class="hint hidden" aria-live="polite"></p>
      <fieldset id="training-difficulty" class="difficulty hidden">
        <legend>Сложность бота</legend>
        <label><input type="radio" name="difficulty" value="easy" />Легко</label>
        <label><input type="radio" name="difficulty" value="medium" checked />Средне</label>
        <label><input type="radio" name="difficulty" value="hard" />Сложно</label>
      </fieldset>
      <button id="name-submit" class="primary" type="submit">Подключиться</button>
      <div id="join-block" class="hidden">
        <div class="divider"><span>или</span></div>
        <div class="join-row">
          <input
            id="join-code"
            maxlength="8"
            placeholder="код"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
          />
          <button id="join" type="button">Войти</button>
        </div>
      </div>
      <button id="name-cancel" class="ghost" type="button">Отмена</button>
    </form>
  </div>

  <section id="lobby" class="panel hidden">
    <h2>Комната создана</h2>
    <div id="invite-code" class="code">—</div>
    <p id="lobby-hint" class="hint">Ждём соперника…</p>
    <button id="copy-link" class="primary">Скопировать ссылку</button>
    <button id="cancel" class="ghost">Отмена</button>
  </section>

  <section id="over" class="panel hidden">
    <h2 id="over-title">Победа</h2>
    <div id="over-score" class="code">0 : 0</div>
    <button id="again" class="primary">Реванш</button>
    <button id="to-menu" class="ghost">Новая игра</button>
  </section>

  <div id="toast" class="hidden"></div>
  <div id="training-controls" class="training-controls hidden">
    <button id="human-invite" class="hidden" type="button">
      Хотите поиграть с человеком?
    </button>
    <button id="exit-training" type="button">Выйти из тренировки</button>
  </div>
</template>
