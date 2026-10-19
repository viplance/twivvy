import assert from 'node:assert/strict';
import fs from 'node:fs';

const resources = new URL('../Twivvy/Resources/', import.meta.url);
const source = JSON.parse(fs.readFileSync(new URL('./ios-locales.json', import.meta.url), 'utf8'));
const languages = ['en','be','es','ru','uk','it','pt','pl','fr','de','tr'];
const placeholders = value => [...value.matchAll(/\{[a-zA-Z]+\}/g)].map(match => match[0]).sort();
function strings(language, name = 'Localizable') {
 const result = {};
 const text = fs.readFileSync(new URL(`${language}.lproj/${name}.strings`, resources), 'utf8');
 for (const line of text.split('\n').filter(line => line.trim())) {
  const match = line.match(/^("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");$/u);
  assert.ok(match, `${language}: invalid strings line: ${line}`);
  const key = JSON.parse(match[1]);
  assert.ok(!Object.hasOwn(result, key), `${language}: duplicate ${key}`);
  result[key] = JSON.parse(match[2]);
 }
 return result;
}
const english = strings('en');
// Brand names, cognates and standard short labels can legitimately match English.
const sameAsEnglish = new Set(['meta.title','native.notice','player.bot','name.code',
 'native.privacy','native.balls','menu.training','dialog.trainingTitle','native.support',
 'native.platform','native.duel','native.codeHint','native.seconds']);
assert.deepEqual(Object.keys(source).sort(), [...languages].sort(), 'iOS override languages');
for (const language of languages) {
 const localized = strings(language), overrides = source[language];
 assert.deepEqual(Object.keys(localized).sort(), Object.keys(english).sort(), `${language}: missing UI keys`);
 assert.deepEqual(Object.keys(overrides).sort(), Object.keys(source.en).sort(), `${language}: missing iOS overrides`);
 for (const [key, value] of Object.entries(localized)) {
  assert.ok(typeof value === 'string' && value.trim(), `${language}: empty ${key}`);
  assert.deepEqual(placeholders(value), placeholders(english[key]), `${language}: ${key} placeholders`);
  if (language !== 'en' && !sameAsEnglish.has(key)) {
   assert.notEqual(value, english[key], `${language}: unexpected English text for ${key}`);
  }
 }
 for (const [key, value] of Object.entries(overrides)) assert.equal(localized[key], value, `${language}: stale ${key}`);
 assert.equal(strings(language, 'InfoPlist').CFBundleDisplayName, localized['meta.title']);
}
function files(folder) {
 return fs.readdirSync(folder, {withFileTypes:true}).flatMap(entry => {
  const path = new URL(entry.name + (entry.isDirectory() ? '/' : ''), folder);
  return entry.isDirectory() ? files(path) : [path];
 });
}
const usedKeys = new Set();
for (const path of files(new URL('../Twivvy/', import.meta.url)).filter(path => /\.(swift|js)$/.test(path.pathname))) {
 const text = fs.readFileSync(path, 'utf8').replace(/\.accessibilityIdentifier\("[^"\n]+"\)/g, '');
 for (const match of text.matchAll(/["']((?:native|menu|dialog|status|error|result|rules|training|action|sound|player|name|meta|tagline)\.[A-Za-z]+)["']/g)) {
  usedKeys.add(match[1]);
 }
}
for (const key of usedKeys) assert.ok(Object.hasOwn(english,key), `UI/bridge references missing key: ${key}`);
console.log(`Validated ${languages.length} complete iOS localizations (${Object.keys(english).length} keys each), placeholders, display names, iOS overrides and ${usedKeys.size} literal UI/bridge references.`);
