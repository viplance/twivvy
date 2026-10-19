import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { supportedLocales, narrationKeys, readTranslations } from './translation-catalog.mjs';

const resources = new URL('../HamsterLab/Resources/', import.meta.url);
const hash = value => createHash('sha256').update(value).digest('hex');
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
const manifest = JSON.parse(fs.readFileSync(new URL('narration-manifest.json', resources), 'utf8'));
assert.equal(manifest.clips.length, supportedLocales.length * narrationKeys.length);
assert.equal(new Set(manifest.clips.map(clip => `${clip.language}/${clip.prompt}`)).size, manifest.clips.length);
for (const locale of supportedLocales) {
 const generated = strings(locale), translated = readTranslations(locale);
 assert.deepEqual(Object.keys(generated).sort(), Object.keys(english).sort(), `${locale}: missing UI keys`);
 assert.deepEqual(Object.keys(translated).sort(), Object.keys(overrides).sort(), `${locale}: missing overrides`);
 for (const [key, value] of Object.entries(generated)) {
  assert.ok(typeof value === 'string' && value.trim(), `${locale}: empty ${key}`);
  assert.deepEqual(placeholders(value), placeholders(english[key]), `${locale}: ${key} placeholders`);
 }
 for (const [key, value] of Object.entries(translated)) assert.equal(generated[key], value, `${locale}: stale ${key}`);
 assert.equal(strings(locale, 'InfoPlist').CFBundleDisplayName, translated['meta.title']);
 assert.ok(generated['lab.tagline'] && !generated['lab.tagline'].includes('\n'), `${locale}: missing single-phrase slogan`);
 assert.ok(!Object.hasOwn(generated, 'tagline.first') && !Object.hasOwn(generated, 'tagline.second'), `${locale}: obsolete two-part slogan`);
 if (locale !== 'en') assert.notEqual(generated['lab.tagline'], english['lab.tagline'], `${locale}: untranslated slogan`);
 for (const key of narrationKeys) {
  const prompt = key.slice(4);
  const clip = manifest.clips.find(clip => clip.language === locale && clip.prompt === prompt);
  assert.ok(clip, `${locale}/${prompt}: missing narration`);
  assert.equal(clip.textSHA256, hash(translated[key]), `${locale}/${prompt}: regenerate narration after translating`);
  const audio = fs.readFileSync(new URL(`${locale}.lproj/narration-${prompt}.m4a`, resources));
  assert.ok(audio.length > 1000 && clip.durationSeconds > 0.2, `${locale}/${prompt}: empty audio`);
  assert.equal(clip.audioSHA256, hash(audio), `${locale}/${prompt}: audio fingerprint mismatch`);
 }
}
console.log(`Validated ${supportedLocales.length} complete localizations (${Object.keys(english).length} keys each) and ${manifest.clips.length} matching narration clips.`);
