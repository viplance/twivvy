import { createI18n } from "vue-i18n";
import { messages, supportedLocales } from "./locales.ts";

export function detectLocale(languages = navigator.languages?.length
  ? navigator.languages
  : [navigator.language]) {
  for (const language of languages) {
    const normalized = language.toLowerCase().replace("_", "-");
    const exact = supportedLocales.find(locale => locale === normalized);
    if (exact) return exact;
    const base = normalized.split("-")[0];
    if (supportedLocales.includes(base)) return base;
  }
  return "en";
}

export const locale = detectLocale();

export const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: "en",
  messages,
  missingWarn: false,
  fallbackWarn: false,
});

export function translate(key: string, named: Record<string, unknown> = {}) {
  return String(i18n.global.t(key, named as never));
}

export function localizeDocument() {
  document.documentElement.lang = locale;
  document.title = translate("meta.title");
  document.querySelector('meta[name="description"]')
    ?.setAttribute("content", translate("meta.description"));
}
