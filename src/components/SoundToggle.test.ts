import { beforeEach, expect, test, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { ref } from "vue";
import { createI18n } from "vue-i18n";
import { messages } from "../locales/index.ts";

// A real ref, so the template re-renders when the preference flips.
const enabled = ref(false);
const state = {
  get enabled() { return enabled.value; },
  set enabled(value: boolean) { enabled.value = value; },
};

vi.mock("../composables/useSound.ts", () => ({
  useSound: () => ({
    enabled,
    toggle: () => { enabled.value = !enabled.value; },
    setEnabled(value: boolean) { enabled.value = value; },
    play() {}, bindUnlockGestures: () => () => {},
  }),
}));

const i18n = createI18n({ legacy: false, locale: "ru", fallbackLocale: "en", messages });

async function mountToggle() {
  const SoundToggle = (await import("./SoundToggle.vue")).default;
  return mount(SoundToggle, { global: { plugins: [i18n] } });
}

beforeEach(() => {
  state.enabled = false;
  vi.resetModules();
});

test("the button reflects the audio preference and toggles it", async () => {
  const wrapper = await mountToggle();
  const button = wrapper.get("#sound-toggle");
  // The stylesheet keys the on/off icon off aria-pressed.
  expect(button.attributes("aria-pressed")).toBe("false");
  expect(button.attributes("title")).toBe(messages.ru.sound.enable);

  await button.trigger("click");
  await wrapper.vm.$nextTick();
  expect(state.enabled).toBe(true);
  expect(button.attributes("aria-pressed")).toBe("true");
  expect(button.attributes("title")).toBe(messages.ru.sound.disable);
});

test("a stored preference is shown on mount", async () => {
  state.enabled = true;
  const wrapper = await mountToggle();
  expect(wrapper.get("#sound-toggle").attributes("aria-pressed")).toBe("true");
});
