import fs from 'node:fs';

import { supportedLocales, readTranslations } from './translation-catalog.mjs';

const source = readTranslations('en');
const keys = Object.keys(source).sort();
const placeholders = value => [...value.matchAll(/\{[a-zA-Z]+\}/g)].map(match=>match[0]).sort();
for (const locale of supportedLocales) {
 const translations = readTranslations(locale);
 if (JSON.stringify(Object.keys(translations).sort()) !== JSON.stringify(keys)) {
  throw new Error(`${locale}: HamsterLab translation keys must match English exactly`);
 }
 for (const key of keys) {
  const value = translations[key];
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${locale}: empty translation for ${key}`);
  if (JSON.stringify(placeholders(value)) !== JSON.stringify(placeholders(source[key]))) {
   throw new Error(`${locale}: mismatched placeholders in ${key}`);
  }
 }
 const folder=new URL(`../HamsterLab/Resources/${locale}.lproj/`,import.meta.url);
 const target=new URL('Localizable.strings',folder);
 const lines=fs.readFileSync(target,'utf8').split('\n')
  .filter(line=>!/^"tagline\.(first|second)" = /.test(line))
  .map(line=>line.replaceAll('Twivvy','HamsterLab').replaceAll('Твивви','ХомаЛаб'));
 for (const [key,value] of Object.entries(translations)) {
  const prefix=JSON.stringify(key)+' = ';
  const index=lines.findIndex(line=>line.startsWith(prefix));
  const line=`${prefix}${JSON.stringify(value)};`;
  if(index<0) lines.push(line); else lines[index]=line;
 }
 fs.writeFileSync(target,lines.join('\n').trim()+'\n');
 fs.writeFileSync(new URL('InfoPlist.strings',folder),`"CFBundleDisplayName" = ${JSON.stringify(translations['meta.title'])};\n`);
}
