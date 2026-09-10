/**
 * Cloudflare Worker for twivvy.e-notix.com
 *
 * Why it exists: room links are paths, e.g. https://twivvy.e-notix.com/KFUEB.
 * No such object is in the bucket, so Google Cloud Storage serves index.html
 * (its configured notFoundPage) but with an HTTP 404 status. The page works,
 * yet the status is wrong for a link people share.
 *
 * This Worker rewrites a room-code path to index.html before it reaches GCS,
 * so the response is a clean 200. Everything else — the site root and
 * Vite's /assets/* output — is passed through untouched.
 *
 * Deploy: Cloudflare dashboard -> Workers & Pages -> Create Worker, paste this
 * file, then add a route: twivvy.e-notix.com/* (zone e-notix.com).
 * The DNS record for twivvy stays CNAME -> c.storage.googleapis.com (proxied).
 */

// Room codes are 4-8 chars from the signalling service's alphabet.
const ROOM_CODE = /^\/[A-Z0-9]{4,8}$/i;

export default {
  async fetch(request) {
    const url = new URL(request.url);

    if (ROOM_CODE.test(url.pathname)) {
      // Ask the origin for the app shell; the browser keeps the pretty URL,
      // and the client reads the room code from window.location itself.
      const target = new URL(request.url);
      target.pathname = "/index.html";

      const response = await fetch(new Request(target, request));
      const body = await response.arrayBuffer();

      return new Response(body, {
        status: 200,
        headers: {
          "content-type": "text/html; charset=utf-8",
          // A room link must never be cached as a specific room's page.
          "cache-control": "no-store",
        },
      });
    }

    return fetch(request);
  },
};
