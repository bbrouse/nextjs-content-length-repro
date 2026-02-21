# Next.js `/_next/data/` Content-Length Reproduction

This repository demonstrates an issue in Next.js where `/_next/data/` responses for statically generated pages lost the `Content-Length` header starting in v15.4.1. Without `Content-Length`, CDNs like AWS CloudFront cannot compress these responses, resulting in a ~4-8x increase in transfer size for JSON payloads.

## The Problem

Starting in Next.js 15.4.1, `/_next/data/<buildId>/<page>.json` responses switched from buffered responses (with `Content-Length`) to streamed responses (`Transfer-Encoding: chunked`). This breaks compression on CDNs that require `Content-Length` to compress origin responses -- most notably AWS CloudFront.

## Root Cause

[PR #80189](https://github.com/vercel/next.js/pull/80189) ("Add response handling inside handlers") moved response handling from `base-server.ts` into the Pages route handler template (`packages/next/src/build/templates/pages.ts`). The new handler constructs the `/_next/data/` JSON response with `Buffer.from()` instead of a plain string:

```typescript
// v15.4.1 (broken) - packages/next/src/build/templates/pages.ts
new RenderResult(
  Buffer.from(JSON.stringify(result.value.pageData)),
  { contentType: 'application/json', metadata: result.value.html.metadata }
)
```

```typescript
// v15.4.0 (working) - packages/next/src/server/base-server.ts
RenderResult.fromStatic(JSON.stringify(cachedData.pageData))
```

`RenderResult.isDynamic` returns `typeof this.response !== 'string'`. A `Buffer` is not a string, so `isDynamic` becomes `true`, which causes `sendRenderResult` in `send-payload.ts` to skip setting `Content-Length` and `ETag` and instead pipe the response as `Transfer-Encoding: chunked`.

The fix is to pass the JSON string directly instead of wrapping it in `Buffer.from()`:

```diff
- new RenderResult(Buffer.from(JSON.stringify(result.value.pageData)), {
+ new RenderResult(JSON.stringify(result.value.pageData), {
    contentType: 'application/json',
    metadata: result.value.html.metadata,
  })
```

## Versions Affected

- **Last working version**: 15.4.0 (published May 30, 2025)
- **First broken version**: 15.4.1 (published July 14, 2025; includes PR #80189 merged June 11, 2025)

Both versions use React 19, so the React version is not a factor. The only change between `before/` and `after/` is the Next.js patch version.

## Repository Structure

```
before/          Next.js 15.4.0 (working -- Content-Length present)
after/           Next.js 15.4.1 (broken -- Transfer-Encoding: chunked)
after-patched/   Next.js 15.4.1 with the one-line fix applied via postinstall
scripts/         compare-headers.sh to automate the comparison
```

All directories contain the same page (`pages/index.js` with `getStaticProps` + `revalidate`) and config (`next.config.js` with `compress: false`).

## Reproducing

### Automated

```bash
chmod +x scripts/compare-headers.sh
./scripts/compare-headers.sh
```

### Manual

```bash
# Build and start the "before" version (v15.4.0)
cd before && npm install && npx next build && npx next start -p 4100 &
BUILD_ID=$(cat before/.next/BUILD_ID)

# Check headers
curl -sD - -o /dev/null "http://localhost:4100/_next/data/$BUILD_ID/index.json"
```

Repeat with `after/` on a different port and compare the headers.

### Testing the Fix

The `after-patched/` directory is a copy of `after/` (v15.4.1) with the fix applied automatically via a `postinstall` script. To verify:

```bash
cd after-patched && npm install && npx next build && npx next start -p 4300 &
BUILD_ID=$(cat after-patched/.next/BUILD_ID)

curl -sD - -o /dev/null "http://localhost:4300/_next/data/$BUILD_ID/index.json"
```

You should see `Content-Length` and `ETag` restored in the response headers.

## Expected Output

**Before (v15.4.0)** -- `Content-Length` present:

```
HTTP/1.1 200 OK
x-nextjs-cache: HIT
x-nextjs-prerender: 1
Cache-Control: s-maxage=60, stale-while-revalidate=31535940
ETag: "q1vm5i1p4f82hh"
Content-Type: application/json
Content-Length: 376469
```

**After (v15.4.1)** -- `Content-Length` missing, chunked encoding:

```
HTTP/1.1 200 OK
x-nextjs-cache: HIT
Cache-Control: s-maxage=60, stale-while-revalidate=31535940
Content-Type: application/json
Transfer-Encoding: chunked
```

**After-Patched (v15.4.1 + fix)** -- `Content-Length` and `ETag` restored:

```
HTTP/1.1 200 OK
x-nextjs-cache: HIT
Cache-Control: s-maxage=60, stale-while-revalidate=31535940
ETag: "q1vm5i1p4f82hh"
Content-Type: application/json
Content-Length: 376469
```

Notable differences between v15.4.0 and unpatched v15.4.1:

- `Content-Length` replaced by `Transfer-Encoding: chunked`
- `ETag` header missing
- `x-nextjs-prerender` header missing

## Why This Matters

Self-hosted Next.js deployments commonly set `compress: false` because the CDN handles compression. AWS CloudFront [requires `Content-Length` to compress origin responses](https://repost.aws/knowledge-center/cloudfront-troubleshoot-compressed-files). When `/_next/data/` responses use chunked transfer encoding, CloudFront passes them through uncompressed.

For JSON-heavy pages (common with `getStaticProps`), this can mean a ~4-8x increase in data transfer to end users.

## Workaround

Enable server-side compression via `compress: true` in `next.config.js` or add compression middleware (e.g. Express `compression`). This shifts CPU load to the origin, which is suboptimal but functional.

## Related

- [PR #80189](https://github.com/vercel/next.js/pull/80189) -- "Add response handling inside handlers" (root cause)
- [PR #45895](https://github.com/vercel/next.js/pull/45895) -- "Disable streaming for pages" (v13.2.0 fix for a similar class of issue)
- [Discussion #38606](https://github.com/vercel/next.js/discussions/38606) -- Same CloudFront + chunked transfer issue from 2022
