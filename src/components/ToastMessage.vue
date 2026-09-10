<script setup lang="ts">
import { useToast } from "../composables/useToast.ts";

const { text, visible } = useToast();
</script>

<template>
  <div id="toast" :class="{ hidden: !visible }">{{ text }}</div>
</template>
