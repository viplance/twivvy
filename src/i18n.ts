import { createI18n } from "vue-i18n";
import { FALLBACK_LOCALE, messages, supportedLocales } from "./locales/index.ts";
import type { LocaleCode, MessageKey, TranslateParams } from "./types/index.ts";

/**
 * Pick the best supported locale for the browser: an exact tag wins, then the
 * bare language, then English. `navigator.languages` is ordered by preference.
 */
export function detectLocale(
  languages: readonly string[] = navigator.languages?.length
    ? navigator.languages
    : [navigator.language],
): LocaleCode {
  for (const language of languages) {
    const normalized = language.toLowerCase().replace("_", "-");
    const exact = supportedLocales.find((locale) => locale === normalized);
    if (exact) return exact;
    const base = normalized.split("-")[0] as LocaleCode;
    if (supportedLocales.includes(base)) return base;
  }
  return FALLBACK_LOCALE;
}

export const locale = detectLocale();

export const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: FALLBACK_LOCALE,
  messages,
  missingWarn: false,
  fallbackWarn: false,
});

/** Translate outside a component, where `$t` is unavailable. */
export function translate(key: MessageKey, named: TranslateParams = {}): string {
  return String(i18n.global.t(key, named as never));
}

/** The document shell is outside the Vue tree, so it is localized by hand. */
export function localizeDocument(): void {
  document.documentElement.lang = locale;
  document.title = translate("meta.title");
  document
    .querySelector('meta[name="description"]')
    ?.setAttribute("content", translate("meta.description"));
}
