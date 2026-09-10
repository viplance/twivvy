/// <reference types="vite/client" />

declare global {
  interface Window {
    __TWIVVY_DECIDE_MS?: number;
    __twivvy?: Record<string, unknown>;
    webkitAudioContext?: typeof AudioContext;
    TWIVVY_SIGNAL_URL?: string;
  }
}

export {};
