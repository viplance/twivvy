import { ref } from "vue";
import { GameAudio } from "../../js/audio.js";

const audio = new GameAudio();
const enabled = ref(audio.enabled);

/** Effects playback plus the toggle's reactive state. */
export function useSound() {
  function setEnabled(value: boolean): void {
    audio.setEnabled(value);
    enabled.value = audio.enabled;
  }

  function toggle(): void {
    setEnabled(!enabled.value);
  }

  function play(name: "turn" | "delivery"): void {
    audio.play(name);
  }

  /**
   * Resume the context inside a trusted gesture — including Safari's release
   * gesture — so later effects play without needing another tap.
   */
  function bindUnlockGestures(): () => void {
    const unlock = () => audio.unlock();
    const types = ["pointerdown", "pointerup", "keydown"] as const;
    for (const type of types) {
      window.addEventListener(type, unlock, { capture: true, passive: true });
    }
    return () => {
      for (const type of types) {
        window.removeEventListener(type, unlock, { capture: true });
      }
    };
  }

  return { enabled, setEnabled, toggle, play, bindUnlockGestures };
}
