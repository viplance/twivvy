import type { LocaleCode } from "../types/i18n.ts";
import { be } from "./be.ts";
import { de } from "./de.ts";
import { en } from "./en.ts";
import { es } from "./es.ts";
import { fr } from "./fr.ts";
import { it } from "./it.ts";
import { pl } from "./pl.ts";
import { pt } from "./pt.ts";
import { ru } from "./ru.ts";
import { tr } from "./tr.ts";
import { uk } from "./uk.ts";

/**
 * English is the reference catalogue: every other locale is checked against it
 * by tools/i18n.test.mjs, and message keys are derived from its shape.
 */
export type ReferenceCatalogue = typeof en;

export const messages = { en, be, es, ru, uk, it, pt, pl, de, tr, fr } as const;

export const supportedLocales = Object.keys(messages) as LocaleCode[];

export const FALLBACK_LOCALE: LocaleCode = "en";
