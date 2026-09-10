<script setup lang="ts">
defineProps<{
  visible: boolean;
  /** The public pool pairs players in twos, so odd presence means someone waits. */
  showHumanInvite: boolean;
}>();

const emit = defineEmits<{ (event: "invite"): void; (event: "exit"): void }>();
</script>

<template>
  <div id="training-controls" class="training-controls" :class="{ hidden: !visible }">
    <button
      id="human-invite"
      type="button"
      :class="{ hidden: !showHumanInvite }"
      @click="emit('invite')"
    >
      {{ $t('training.humanInvite') }}
    </button>
    <button id="exit-training" type="button" @click="emit('exit')">
      {{ $t('training.exit') }}
    </button>
  </div>
</template>
