import assert from 'node:assert/strict';
import fs from 'node:fs';
import { supportedLocales, standaloneLocales, readTranslations } from './translation-catalog.mjs';

const resources = new URL('../HamsterLab/Resources/', import.meta.url);
const placeholders = value => [...value.matchAll(/\{[a-zA-Z]+\}/g)].map(match => match[0]).sort();
function strings(locale, name = 'Localizable') {
 const text = fs.readFileSync(new URL(`${locale}.lproj/${name}.strings`, resources), 'utf8');
 const result = {};
 for (const line of text.split('\n').filter(line => line.trim())) {
  const match = line.match(/^("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");$/u);
  assert.ok(match, `${locale}: invalid strings line: ${line}`);
  const key = JSON.parse(match[1]);
  assert.ok(!Object.hasOwn(result, key), `${locale}: duplicate key ${key}`);
  result[key] = JSON.parse(match[2]);
 }
 return result;
}
const english = strings('en');
const overrides = readTranslations('en');
for (const locale of supportedLocales) {
 const generated = strings(locale), translated = readTranslations(locale);
 assert.deepEqual(Object.keys(generated).sort(), Object.keys(english).sort(), `${locale}: missing UI keys`);
 const expected=standaloneLocales.includes(locale) ? english : overrides;
 assert.deepEqual(Object.keys(translated).sort(), Object.keys(expected).sort(), `${locale}: missing translations`);
 for (const [key, value] of Object.entries(generated)) {
  assert.ok(typeof value === 'string' && value.trim(), `${locale}: empty ${key}`);
  assert.deepEqual(placeholders(value), placeholders(english[key]), `${locale}: ${key} placeholders`);
 }
 for (const [key, value] of Object.entries(translated)) assert.equal(generated[key], value, `${locale}: stale ${key}`);
 assert.equal(strings(locale, 'InfoPlist').CFBundleDisplayName, translated['meta.title']);
 assert.ok(generated['lab.tagline'] && !generated['lab.tagline'].includes('\n'), `${locale}: missing single-phrase slogan`);
 assert.ok(!Object.hasOwn(generated, 'tagline.first') && !Object.hasOwn(generated, 'tagline.second'), `${locale}: obsolete two-part slogan`);
 if (locale !== 'en') assert.notEqual(generated['lab.tagline'], english['lab.tagline'], `${locale}: untranslated slogan`);
}
console.log(`Validated ${supportedLocales.length} complete localizations (${Object.keys(english).length} keys each).`);
