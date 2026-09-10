<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { DEFAULT_DIFFICULTY, MAX_PLAYER_NAME_LENGTH, NAME_DIALOG_COPY } from "../constants/index.ts";
import { normalizePlayerName } from "../composables/usePlayerName.ts";
import type { Difficulty, NamePrompt } from "../types/index.ts";

const { t } = useI18n();

const props = defineProps<{
  prompt: NamePrompt | null;
  initialName: string;
  onlineCount: number;
  /** Set while matchmaking runs, which also locks the form. */
  status: string;
  busy: boolean;
  submitLabel: string;
}>();

const emit = defineEmits<{
  (event: "submit", payload: { name: string; difficulty: Difficulty }): void;
  (event: "join", payload: { code: string; name: string }): void;
  (event: "cancel"): void;
}>();

const name = ref(props.initialName);
const code = ref("");
const difficulty = ref<Difficulty>(DEFAULT_DIFFICULTY);
const nameInput = ref<HTMLInputElement | null>(null);
const codeInput = ref<HTMLInputElement | null>(null);

const mode = computed(() => props.prompt?.mode ?? null);
const title = computed(() =>
  mode.value ? t(NAME_DIALOG_COPY[mode.value].title) : "",
);
/** Entering a code belongs to "play with a friend"; other modes have their own route. */
const showJoinBlock = computed(() => mode.value === "create");

watch(
  () => props.prompt,
  async (prompt) => {
    if (!prompt) return;
    name.value = props.initialName;
    code.value = "";
    nameInput.value?.setCustomValidity("");
    await nextTick();
    nameInput.value?.focus();
  },
  { immediate: true },
);

/** Report an empty name through the platform's own validation bubble. */
function requireName(): string | null {
  const value = normalizePlayerName(name.value);
  if (!value) {
    nameInput.value?.setCustomValidity(t("error.nameRequired"));
    nameInput.value?.reportValidity();
    return null;
  }
  nameInput.value?.setCustomValidity("");
  return value;
}

function submit(): void {
  const value = requireName();
  if (!value) return;
  emit("submit", { name: value, difficulty: difficulty.value });
}

function join(): void {
  const trimmed = code.value.trim().toUpperCase();
  if (!trimmed) {
    codeInput.value?.focus();
    return;
  }
  const value = requireName();
  if (!value) return;
  emit("join", { code: trimmed, name: value });
}
</script>

<template>
  <div id="name-modal" class="modal-backdrop" :class="{ hidden: !prompt }" role="presentation">
    <form
      id="name-form"
      class="panel modal"
      aria-modal="true"
      aria-labelledby="name-title"
      role="dialog"
      @submit.prevent="submit"
    >
      <h2 id="name-title">{{ title }}</h2>
      <label class="name-field" for="player-name">
        <span>{{ $t('name.label') }}</span>
        <input
          id="player-name"
          ref="nameInput"
          v-model="name"
          :maxlength="MAX_PLAYER_NAME_LENGTH"
          autocomplete="nickname"
          enterkeyhint="done"
          :disabled="busy"
          required
          @input="nameInput?.setCustomValidity('')"
        />
      </label>
      <p
        id="online-count"
        class="online-count"
        :class="{ hidden: mode !== 'online' }"
        aria-live="polite"
      >
        {{ $t('name.online') }} <strong>{{ onlineCount }}</strong>
      </p>
      <p id="matchmaking-status" class="hint" :class="{ hidden: !status }" aria-live="polite">
        {{ status }}
      </p>
      <fieldset
        id="training-difficulty"
        class="difficulty"
        :class="{ hidden: mode !== 'training' }"
      >
        <legend>{{ $t('name.difficulty') }}</legend>
        <label>
          <input v-model="difficulty" type="radio" name="difficulty" value="easy" />
          {{ $t('name.easy') }}
        </label>
        <label>
          <input v-model="difficulty" type="radio" name="difficulty" value="medium" />
          {{ $t('name.medium') }}
        </label>
        <label>
          <input v-model="difficulty" type="radio" name="difficulty" value="hard" />
          {{ $t('name.hard') }}
        </label>
      </fieldset>
      <button id="name-submit" class="primary" type="submit" :disabled="busy">
        {{ submitLabel }}
      </button>
      <div id="join-block" :class="{ hidden: !showJoinBlock }">
        <div class="divider"><span>{{ $t('name.or') }}</span></div>
        <div class="join-row">
          <input
            id="join-code"
            ref="codeInput"
            v-model="code"
            maxlength="8"
            :placeholder="$t('name.code')"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            @keydown.enter.prevent="join"
          />
          <button id="join" type="button" @click="join">{{ $t('action.join') }}</button>
        </div>
      </div>
      <button id="name-cancel" class="ghost" type="button" @click="emit('cancel')">
        {{ $t('action.cancel') }}
      </button>
    </form>
  </div>
</template>
