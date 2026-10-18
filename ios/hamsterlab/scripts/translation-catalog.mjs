import fs from 'node:fs';

export const supportedLocales = ['en','be','es','ru','uk','it','pt','pl','fr','de','tr'];
export const narrationKeys = ['lab.welcome','lab.begin','lab.win','lab.finish'];
export function readTranslations(locale) {
 return JSON.parse(fs.readFileSync(new URL(`./locales/${locale}.json`,import.meta.url),'utf8'));
}
