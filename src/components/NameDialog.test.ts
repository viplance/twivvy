import { describe, expect, test, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createI18n } from "vue-i18n";
import NameDialog from "./NameDialog.vue";
import { messages } from "../locales/index.ts";
import type { NamePrompt } from "../types/index.ts";

const i18n = createI18n({ legacy: false, locale: "ru", fallbackLocale: "en", messages });

function mountDialog(prompt: NamePrompt | null, props: Record<string, unknown> = {}) {
  return mount(NameDialog, {
    global: { plugins: [i18n] },
    props: {
      prompt, initialName: "", onlineCount: 0, status: "", busy: false,
      submitLabel: "OK", ...props,
    },
  });
}

test("the dialog pre-fills the saved browser name", async () => {
  const wrapper = mountDialog({ mode: "create", code: null }, { initialName: "Сохранённое имя" });
  await wrapper.vm.$nextTick();
  expect(wrapper.get<HTMLInputElement>("#player-name").element.value).toBe("Сохранённое имя");
});

test("submitting emits the normalized name", async () => {
  const wrapper = mountDialog({ mode: "online", code: null });
  await wrapper.get("#player-name").setValue("  Новый   игрок  ");
  await wrapper.get("#name-form").trigger("submit");
  expect(wrapper.emitted("submit")?.[0]).toEqual([
    { name: "Новый игрок", difficulty: "medium" },
  ]);
});

test("an empty name reports validity instead of submitting", async () => {
  const wrapper = mountDialog({ mode: "create", code: null });
  const input = wrapper.get<HTMLInputElement>("#player-name").element;
  const report = vi.spyOn(input, "reportValidity").mockReturnValue(false);
  await wrapper.get("#player-name").setValue("   ");
  await wrapper.get("#name-form").trigger("submit");
  expect(wrapper.emitted("submit")).toBeUndefined();
  expect(report).toHaveBeenCalled();
});

describe("mode-specific blocks", () => {
  test("online shows the player count and hides the join block", () => {
    const wrapper = mountDialog({ mode: "online", code: null }, { onlineCount: 7 });
    expect(wrapper.get("#online-count").classes()).not.toContain("hidden");
    expect(wrapper.get("#join-block").classes()).toContain("hidden");
    expect(wrapper.get("#online-count").text()).toContain("7");
  });

  test("entering a code belongs to play-with-a-friend only", () => {
    expect(mountDialog({ mode: "create", code: null }).get("#join-block").classes())
      .not.toContain("hidden");
    for (const mode of ["join", "online", "training"] as const) {
      expect(mountDialog({ mode, code: null }).get("#join-block").classes())
        .toContain("hidden");
    }
  });

  test("training shows the difficulty picker", () => {
    const wrapper = mountDialog({ mode: "training", code: null });
    expect(wrapper.get("#training-difficulty").classes()).not.toContain("hidden");
  });
});

test("joining by code emits the code and name together", async () => {
  const wrapper = mountDialog({ mode: "create", code: null }, { initialName: "Игрок" });
  await wrapper.vm.$nextTick();
  await wrapper.get("#join-code").setValue("hmh9t");
  await wrapper.get("#join").trigger("click");
  expect(wrapper.emitted("join")?.[0]).toEqual([{ code: "HMH9T", name: "Игрок" }]);
});

test("an empty code focuses the field rather than joining", async () => {
  const wrapper = mountDialog({ mode: "create", code: null }, { initialName: "Игрок" });
  await wrapper.get("#join").trigger("click");
  expect(wrapper.emitted("join")).toBeUndefined();
});

test("a busy dialog locks the name field and the submit button", () => {
  const wrapper = mountDialog({ mode: "online", code: null }, {
    busy: true, status: "Ищем соперника…", submitLabel: "Ищем…",
  });
  expect(wrapper.get<HTMLInputElement>("#player-name").element.disabled).toBe(true);
  expect(wrapper.get<HTMLButtonElement>("#name-submit").element.disabled).toBe(true);
  expect(wrapper.get("#matchmaking-status").text()).toBe("Ищем соперника…");
});
