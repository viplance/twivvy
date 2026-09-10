<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { BoardView } from "../../js/view.js";
import type { RotationDir } from "../types/index.ts";

const emit = defineEmits<{
  (event: "ready", view: BoardView): void;
  (event: "drag-start", platform: number, allow: (value: boolean) => void): void;
  (event: "drag", platform: number, dir: RotationDir | null): void;
  (event: "release"): void;
}>();

const canvas = ref<HTMLCanvasElement | null>(null);
let view: BoardView | null = null;

onMounted(() => {
  if (!canvas.value) return;
  view = new BoardView(canvas.value, {
    onPlatformDragStart(platform) {
      // The parent owns match state, so it decides through this callback.
      let allowed = false;
      emit("drag-start", platform, (value) => {
        allowed = value;
      });
      return allowed;
    },
    onPlatformDrag(platform, dir) {
      emit("drag", platform, dir);
    },
    onPlatformRelease() {
      emit("release");
    },
  });
  view.start();
  emit("ready", view);
});

onBeforeUnmount(() => {
  view?.setInteractionEnabled(false);
  view = null;
});
</script>

<template>
  <canvas id="scene" ref="canvas"></canvas>
</template>
