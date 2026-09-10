<script setup lang="ts">
defineProps<{
  visible: boolean;
  timerFraction: number;
  paused: boolean;
}>();
</script>

<template>
  <div id="hud" :class="{ hidden: !visible }">
    <div class="timer-row">
      <div class="timer-bar">
        <div id="timer-fill" :style="{ transform: `scaleX(${timerFraction})` }"></div>
      </div>
    </div>
    <p id="pause-status" :class="{ hidden: !paused }" role="status" aria-live="polite">
      {{ $t('status.peerDisconnected') }}
    </p>
  </div>
</template>
