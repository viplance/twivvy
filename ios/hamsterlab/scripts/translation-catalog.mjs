import fs from 'node:fs';

// These languages have complete native catalogs and do not inherit web copy.
export const standaloneLocales = ['zh-Hans','ja','hi','ar','fa'];
export const supportedLocales = ['en','be','es','ru','uk','it','pt','pl','fr','de','tr',...standaloneLocales];
export function readTranslations(locale) {
 return JSON.parse(fs.readFileSync(new URL(`./locales/${locale}.json`,import.meta.url),'utf8'));
}
