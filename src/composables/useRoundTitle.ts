import { onScopeDispose, ref } from "vue";
import { TICKS } from "../../js/rules.js";
import { ROUND_TITLE_MS } from "../constants/index.ts";
import { translate } from "../i18n.ts";

/** The centred "Round N of M" banner shown as each decision round opens. */
export function useRoundTitle() {
  const text = ref("");
  const visible = ref(false);
  /** Restarts the CSS keyframes when a new round lands mid-animation. */
  const playing = ref(false);
  const announced = ref(0);
  let timer: ReturnType<typeof setTimeout> | undefined;

  function hide(): void {
    clearTimeout(timer);
    timer = undefined;
    playing.value = false;
    visible.value = false;
  }

  function announce(round: number): void {
    if (round === announced.value || round < 1 || round > TICKS) return;
    announced.value = round;
    clearTimeout(timer);
    text.value = translate("status.round", { round, total: TICKS });
    visible.value = true;
    // Drop the class so the next tick can re-add it and replay the keyframes.
    playing.value = false;
    requestAnimationFrame(() => {
      if (visible.value) playing.value = true;
    });
    timer = setTimeout(hide, ROUND_TITLE_MS);
  }

  function reset(round = 0): void {
    announced.value = round;
    hide();
  }

  onScopeDispose(() => clearTimeout(timer));

  return { text, visible, playing, announce, hide, reset };
}
