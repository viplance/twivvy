<script setup lang="ts">
import type { NamePromptMode } from "../types/index.ts";

defineProps<{ visible: boolean }>();

const emit = defineEmits<{ (event: "open", mode: NamePromptMode): void }>();
</script>

<template>
  <main id="menu" class="panel" :class="{ hidden: !visible }">
    <h1>{{ $t('meta.title') }}</h1>
    <p class="tagline">
      {{ $t('tagline.first') }}<br />{{ $t('tagline.second') }}
    </p>

    <button id="create" class="primary" @click="emit('open', 'create')">
      {{ $t('menu.friend') }}
    </button>
    <button id="play-online" @click="emit('open', 'online')">{{ $t('menu.online') }}</button>
    <button id="training" @click="emit('open', 'training')">{{ $t('menu.training') }}</button>

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
</template>
