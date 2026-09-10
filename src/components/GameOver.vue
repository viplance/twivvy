<script setup lang="ts">
defineProps<{
  visible: boolean;
  title: string;
  myScore: number;
  foeScore: number;
  canRematch: boolean;
  rematchPending: boolean;
}>();

const emit = defineEmits<{ (event: "rematch"): void; (event: "menu"): void }>();
</script>

<template>
  <section id="over" class="panel" :class="{ hidden: !visible }">
    <h2 id="over-title">{{ title }}</h2>
    <div id="over-score" class="code">{{ myScore }} : {{ foeScore }}</div>
    <button
      id="again"
      class="primary"
      :class="{ hidden: !canRematch }"
      :disabled="rematchPending"
      @click="emit('rematch')"
    >
      {{ rematchPending ? $t('status.waitingOpponent') : $t('action.rematch') }}
    </button>
    <button id="to-menu" class="ghost" @click="emit('menu')">{{ $t('action.newGame') }}</button>
  </section>
</template>
