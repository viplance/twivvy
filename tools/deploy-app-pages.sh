#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep Cloudflare from injecting its analytics beacon into these static pages.
gsutil -h 'Content-Type:text/html; charset=utf-8' \
  -h 'Cache-Control:public, max-age=300, no-transform' \
  cp public/privacy.html public/support.html gs://twivvy.e-notix.com/

# AASA has no file extension; its JSON MIME type must be explicit.
gsutil -h 'Content-Type:application/json' \
  -h 'Cache-Control:public, max-age=300, no-transform' \
  cp public/.well-known/apple-app-site-association \
  gs://twivvy.e-notix.com/.well-known/apple-app-site-association
