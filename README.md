# Next.js `/_next/data/` Content-Length Regression

This repository demonstrates a regression in Next.js where `/_next/data/` responses for statically generated pages lost the `Content-Length` header starting in v15.4.1. Without `Content-Length`, CDNs like AWS CloudFront cannot compress these responses, resulting in a ~4-8x increase in transfer size for JSON payloads.

## The Problem

Starting in Next.js 15.4.1, `/_next/data/<buildId>/<page>.json` responses switched from buffered responses (with `Content-Length`) to streamed responses (`Transfer-Encoding: chunked`). This breaks compression on CDNs that require `Content-Length` to compress origin responses -- most notably AWS CloudFront.

This is a regression because [PR #45895](https://github.com/vercel/next.js/pull/45895) explicitly disabled streaming for Pages Router in v13.2.0 to prevent this class of issue. The likely re-introduction came via [PR #81048](https://github.com/vercel/next.js/pull/81048), which switched React server builds from edge/browser to Node.js-native builds, causing `RenderResult.response` to be a stream instead of a string.

## Versions Affected

- **Last working version**: 15.4.0
- **First broken version**: 15.4.1

Both versions use React 19, so the React version is not a factor. The only change between `before/` and `after/` is the Next.js patch version.

## Repository Structure

```
before/    Next.js 15.4.0 (working -- Content-Length present)
after/     Next.js 15.4.1 (broken -- Transfer-Encoding: chunked)
scripts/   compare-headers.sh to automate the comparison
```

Both `before/` and `after/` contain the exact same page (`pages/index.js` with `getStaticProps` + `revalidate`) and config (`next.config.js` with `compress: false`).

## Reproducing

### Automated

```bash
chmod +x scripts/compare-headers.sh
./scripts/compare-headers.sh
```

### Manual

```bash
# Build and start the "before" version (v15.4.0)
cd before && npx next build && npx next start -p 4100 &
BUILD_ID=$(cat before/.next/BUILD_ID)

# Check headers
curl -sD - -o /dev/null "http://localhost:4100/_next/data/$BUILD_ID/index.json"
```

Repeat with `after/` on a different port and compare the headers.

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

Notable differences beyond `Content-Length` vs `Transfer-Encoding`:

- `x-nextjs-prerender` header is also missing in v15.4.1
- `ETag` header is also missing in v15.4.1

## Why This Matters

Self-hosted Next.js deployments commonly set `compress: false` because the CDN handles compression. AWS CloudFront [requires `Content-Length` to compress origin responses](https://repost.aws/knowledge-center/cloudfront-troubleshoot-compressed-files). When `/_next/data/` responses use chunked transfer encoding, CloudFront passes them through uncompressed.

For JSON-heavy pages (common with `getStaticProps`), this can mean a ~4-8x increase in data transfer to end users.

## Workaround

Enable server-side compression via `compress: true` in `next.config.js` or add compression middleware (e.g. Express `compression`). This shifts CPU load to the origin, which is suboptimal but functional.

## Related Issues

- [Discussion #38606](https://github.com/vercel/next.js/discussions/38606) -- Same CloudFront + chunked transfer issue from 2022
- [PR #45895](https://github.com/vercel/next.js/pull/45895) -- "Disable streaming for pages" (v13.2.0 fix for this class of issue)
- [PR #81048](https://github.com/vercel/next.js/pull/81048) -- "[node-webstreams] Use React builds for Node.js" (likely re-introduction)
