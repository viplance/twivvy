// Short effects share one gesture-unlocked context; each play gets its own
// source so a new effect never cuts off an effect that is already playing.
const EFFECTS = {
  delivery: new URL('../sound/magic_hole_in.mp3', import.meta.url),
  turn: new URL('../sound/rising_wind.mp3', import.meta.url),
};
const SOUND_KEY = 'twivvy-sound-enabled';

export class GameAudio {
  constructor() {
    this.enabled = false;
    try { this.enabled = localStorage.getItem(SOUND_KEY) === 'true'; } catch {}
    this.buffers = new Map();
    this.data = Object.entries(EFFECTS).map(([name, url]) => [name,
      fetch(url).then(response => response.ok ? response.arrayBuffer() : null).catch(() => null),
    ]);
  }

  setEnabled(enabled) {
    this.enabled = Boolean(enabled);
    try { localStorage.setItem(SOUND_KEY, String(this.enabled)); } catch {}
    // Also silence effects that are already playing.
    if (this.gain) this.gain.gain.value = this.enabled ? 0.7 : 0;
    if (this.enabled) this.unlock();
  }

  unlock() {
    if (!this.enabled) return;
    try {
      if (!this.context) {
        const Context = window.AudioContext || window.webkitAudioContext;
        if (!Context) return;
        this.context = new Context();
        this.gain = this.context.createGain();
        this.gain.gain.value = 0.7;
        this.gain.connect(this.context.destination);
        for (const [name, data] of this.data) {
          data.then(bytes => bytes && this.context.decodeAudioData(bytes))
            .then(buffer => { if (buffer) this.buffers.set(name, buffer); })
            .catch(() => {});
        }
      }
      if (this.context.state !== 'running') this.context.resume().catch(() => {});
    } catch { /* Audio is optional; unavailable devices must not stop a turn. */ }
  }

  play(name) {
    // Never queue a stale effect to play when a background tab is reopened.
    if (!this.enabled || document.hidden || this.context?.state !== 'running') return;
    const buffer = this.buffers.get(name);
    if (!buffer) return;
    try {
      const source = this.context.createBufferSource();
      source.buffer = buffer;
      source.connect(this.gain);
      source.onended = () => source.disconnect();
      source.start();
    } catch { /* A device or browser audio failure must not affect the match. */ }
  }
}
