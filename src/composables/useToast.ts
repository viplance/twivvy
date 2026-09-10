import { onScopeDispose, readonly, ref } from "vue";
import { TOAST_MS } from "../constants/index.ts";

const text = ref("");
const visible = ref(false);
let timer: ReturnType<typeof setTimeout> | undefined;

/** One transient status line, shared by every caller. */
export function useToast() {
  function toast(message: string, ms: number = TOAST_MS): void {
    text.value = message;
    visible.value = true;
    clearTimeout(timer);
    timer = setTimeout(() => {
      visible.value = false;
    }, ms);
  }

  function hide(): void {
    clearTimeout(timer);
    visible.value = false;
  }

  return { text: readonly(text), visible: readonly(visible), toast, hide };
}

/** Cancel a pending hide when the owning component goes away. */
export function useToastLifecycle() {
  onScopeDispose(() => clearTimeout(timer));
}
