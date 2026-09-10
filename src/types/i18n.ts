/** Message-catalogue contract shared by every locale file. */

/** A locale is two levels deep: a namespace of leaf strings. */
export type LocaleMessages = Readonly<Record<string, Readonly<Record<string, string>>>>;

/** Locale codes the UI ships translations for. */
export type LocaleCode =
  | "en" | "be" | "es" | "ru" | "uk" | "it" | "pt" | "pl" | "de" | "tr" | "fr";

/**
 * Dotted message keys, derived from the English catalogue so a typo in a
 * `translate()` call fails the type-check instead of rendering the raw key.
 */
export type MessageKeyOf<Catalogue> = Catalogue extends Readonly<Record<string, unknown>>
  ? {
      [Namespace in keyof Catalogue & string]: Catalogue[Namespace] extends Readonly<
        Record<string, unknown>
      >
        ? `${Namespace}.${keyof Catalogue[Namespace] & string}`
        : never;
    }[keyof Catalogue & string]
  : never;

/** Values interpolated into a message's `{placeholder}` slots. */
export type TranslateParams = Readonly<Record<string, string | number>>;
