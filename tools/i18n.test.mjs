import { test } from "node:test";
import assert from "node:assert/strict";
import { messages, supportedLocales } from "../src/locales.ts";
import { detectLocale } from "../src/i18n.ts";

const requestedLocales = ["en", "be", "es", "ru", "uk", "it", "pt", "pl", "fr", "de", "tr"];
const localizedTitles = {
  en: "Twivvy", be: "Перакрут", es: "Giro", ru: "Перекрут", uk: "Перекрут",
  it: "Giravolta", pt: "Reviravolta", pl: "Zakręt", fr: "Rotation", de: "Drehung", tr: "Dönüş",
};

function leafKeys(value, prefix = "") {
  return Object.entries(value).flatMap(([key, child]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === "object" ? leafKeys(child, path) : [path];
  });
}

function get(value, path) {
  return path.split(".").reduce((part, key) => part?.[key], value);
}

test("all requested UI locales contain the complete message set", () => {
  assert.deepEqual([...supportedLocales].sort(), [...requestedLocales].sort());
  const referenceKeys = leafKeys(messages.en).sort();
  for (const locale of requestedLocales) {
    assert.deepEqual(leafKeys(messages[locale]).sort(), referenceKeys, `${locale} message keys`);
    for (const key of referenceKeys) {
      assert.equal(typeof get(messages[locale], key), "string", `${locale}.${key}`);
      assert.notEqual(get(messages[locale], key).trim(), "", `${locale}.${key}`);
    }
  }
});

test("browser locale detection supports regions and language priority", () => {
  assert.equal(detectLocale(["fr-CA"]), "fr");
  assert.equal(detectLocale(["pt_BR"]), "pt");
  assert.equal(detectLocale(["uk-UA"]), "uk");
  assert.equal(detectLocale(["de-DE"]), "de");
  assert.equal(detectLocale(["tr-TR"]), "tr");
  assert.equal(detectLocale(["ja-JP", "es-MX"]), "es");
});

test("unknown browser locales fall back to English", () => {
  assert.equal(detectLocale(["ja-JP"]), "en");
  assert.equal(detectLocale([]), "en");
});

test("every locale has its localized game title", () => {
  for (const locale of requestedLocales) {
    assert.equal(messages[locale].meta.title, localizedTitles[locale]);
  }
});
