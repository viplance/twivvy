<script setup lang="ts">
defineProps<{
  visible: boolean;
  code: string;
  hint: string;
  showCopy: boolean;
}>();

const emit = defineEmits<{ (event: "copy"): void; (event: "cancel"): void }>();
</script>

<template>
  <section id="lobby" class="panel" :class="{ hidden: !visible }">
    <h2>{{ $t('lobby.created') }}</h2>
    <div id="invite-code" class="code">{{ code || '—' }}</div>
    <p id="lobby-hint" class="hint">{{ hint }}</p>
    <button id="copy-link" class="primary" :class="{ hidden: !showCopy }" @click="emit('copy')">
      {{ $t('action.copy') }}
    </button>
    <button id="cancel" class="ghost" @click="emit('cancel')">{{ $t('action.cancel') }}</button>
  </section>
</template>
