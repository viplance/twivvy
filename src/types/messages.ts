import type { ReferenceCatalogue } from "../locales/index.ts";
import type { MessageKeyOf } from "./i18n.ts";

/**
 * Every valid dotted key, bound to the English catalogue. Import this rather
 * than the generic helper so a mistyped key is caught at the call site.
 */
export type MessageKey = MessageKeyOf<ReferenceCatalogue>;
