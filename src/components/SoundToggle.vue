<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { useSound } from "../composables/useSound.ts";

const { t } = useI18n();
const { enabled, toggle } = useSound();

const title = computed(() => t(enabled.value ? "sound.disable" : "sound.enable"));
/** The stylesheet swaps the on/off icon on this attribute, so it must be a string. */
const pressed = computed(() => (enabled.value ? "true" : "false"));
</script>

<template>
  <button
    id="sound-toggle"
    type="button"
    :aria-label="$t('sound.label')"
    :aria-pressed="pressed"
    :title="title"
    @click="toggle"
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
</template>
