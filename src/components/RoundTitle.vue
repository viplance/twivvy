<script setup lang="ts">
defineProps<{
  text: string;
  visible: boolean;
  playing: boolean;
}>();
</script>

<template>
  <div
    id="round-title"
    class="round-title"
    :class="{ hidden: !visible, playing }"
    role="status"
    aria-live="polite"
  >
    {{ text }}
  </div>
</template>
