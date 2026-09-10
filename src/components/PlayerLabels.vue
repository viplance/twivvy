<script setup lang="ts">
import type { CSSProperties } from "vue";

defineProps<{
  visible: boolean;
  ownName: string;
  opponentName: string;
  ownStyle: CSSProperties;
  opponentStyle: CSSProperties;
}>();
</script>

<template>
  <div id="player-labels" class="player-labels" :class="{ hidden: !visible }" aria-live="polite">
    <div id="opponent-name" class="receiver-name opponent-name" :style="opponentStyle">
      {{ opponentName }}
    </div>
    <div id="own-name" class="receiver-name own-name" :style="ownStyle">
      {{ ownName }}
    </div>
  </div>
</template>
