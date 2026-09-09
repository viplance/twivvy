import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../js/audio.js', import.meta.url), 'utf8');
function setup(value = null, storageBlocked = false) {
  const storage = new Map(value === null ? [] : [['twivvy-sound-enabled', value]]);
  let starts = 0;
  const sandbox = {
    URL,
    fetch: async () => ({ ok: false }),
    document: { hidden: false },
    localStorage: {
      getItem(key) { if (storageBlocked) throw Error('blocked'); return storage.get(key); },
      setItem(key, value) { if (storageBlocked) throw Error('blocked'); storage.set(key, value); },
    },
    window: { AudioContext: class {
      state = 'running';
      createGain() { return { gain: { value: 0 }, connect() {} }; }
      createBufferSource() { return { connect() {}, start() { starts++; } }; }
    } },
  };
  vm.createContext(sandbox);
  vm.runInContext(source.replace('export class GameAudio', 'globalThis.GameAudio = class GameAudio')
    .replaceAll('import.meta.url', JSON.stringify(new URL('../js/audio.js', import.meta.url).href)), sandbox);
  const audio = new sandbox.GameAudio();
  audio.buffers.set('turn', {});
  return { audio, storage, sandbox, starts: () => starts };
}

test('sound defaults to off and does not create a context on gestures', () => {
  const { audio, starts } = setup();
  audio.unlock();
  audio.play('turn');
  assert.equal(audio.enabled, false);
  assert.equal(audio.context, undefined);
  assert.equal(starts(), 0);
});

test('sound preference persists, restores, and silences active effects', () => {
  const { audio, storage, starts, sandbox } = setup();
  audio.setEnabled(true);
  audio.play('turn');
  assert.equal(starts(), 1);
  assert.equal(storage.get('twivvy-sound-enabled'), 'true');
  assert.equal(new sandbox.GameAudio().enabled, true);
  audio.setEnabled(false);
  assert.equal(audio.gain.gain.value, 0);
  audio.play('turn');
  assert.equal(starts(), 1);
  assert.equal(storage.get('twivvy-sound-enabled'), 'false');
  assert.equal(new sandbox.GameAudio().enabled, false);
  audio.setEnabled(true);
  assert.equal(audio.gain.gain.value, 0.7);
  audio.play('turn');
  assert.equal(starts(), 2);
});

test('unavailable storage and malformed preferences are safe', () => {
  assert.equal(setup('invalid').audio.enabled, false);
  const { audio, starts } = setup(null, true);
  assert.equal(audio.enabled, false);
  audio.setEnabled(true);
  audio.play('turn');
  assert.equal(starts(), 1);
});
