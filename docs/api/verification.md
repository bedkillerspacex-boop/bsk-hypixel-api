# Documentation verification record

## Implementation baseline

The current alignment uses service commit [`75ec603`](https://github.com/bedkillerspacex-boop/bsk-qqbot/commit/75ec6037a5cd6f6e59bfde10bf8fb03a74c4d7a9), production release `20261002064434-4520d9e5dc`. The service repository was inspected for routes, response generation, quota settlement, version parsing and offline contract tests.

## Checks

2026-10-02 actual results: Markdown links/anchors/JSON passed; both JSON schemas and four bancheck examples matched real offline handler output; the 16 credential-free public probes passed. The service's full isolated tests ran 1,148 cases with zero failures/errors and five documented skips. Those service tests are separate from this documentation checker.

- `python -B tools/check_docs.py`: validates relative links, anchors and JSON fences.
- `python -B tools/check_contract.py`: checks both version directories, permanent parameter IDs, proxy timing/rate/cache statements and bancheck billing.
- `python -B tools/probe_public_api.py`: credential-free error/discovery probes only; it does not prove successful authenticated requests.

The historical `REFERENCE.md` is byte-preserved documentation history and is exempt from normalization checks. It contains later historical material, so it must not be treated as a precise release-day production contract.

### CI scope

The required documentation job validates links, JSON, schemas and documentation contracts without accessing the private service repository. The separate implementation comparison requires the repository secret `DOCS_IMPLEMENTATION_TOKEN`, with read-only Contents access to `bsk-qqbot`. Without that secret (including fork PR events where it is unavailable), its summary explicitly reports **NOT RUN**. A successful documentation job does not establish source alignment. Configured but invalid credentials or a failed comparison remain failures. The baseline comparison recorded above was actually run locally.

## Known implementation gaps documented honestly

- Some modern error messages and array values can remain Chinese even though the modern envelope says `locale: en`.
- `/api/bancheck` does local index lookup and does not resolve an arbitrary name through Mojang on every request; UUID is the stable lookup key.
- The registry describes BSK-managed request parameters. Arbitrary upstream proxy parameters are governed by the upstream API and have no local parameter ID.
- Several body aliases declared in parameter metadata are not read by their handler. They are listed explicitly in the registry documentation; no IDs were renumbered.
- `X-Quota-Cost` is a theoretical size tier rather than final settlement. Bugland uses different failure accounting; legacy routes share current billing logic.
- Card display cell IDs may be empty for Chinese labels; the numeric request-parameter registry remains separate and stable.
- Quota's zero-cost header applies after its handler is entered; an earlier concurrency rejection uses the raw responder and may advertise theoretical cost 1 despite charging nothing.
- denick/bancheck do not pass client IP to the short-lived token validator; token support cannot be assumed identical across endpoints.

There is no documentation site build project here. JSON Schema validation and offline snapshots cover the examples explicitly checked, not every third-party raw response. No real API keys, tokens, email addresses or production quota mutations were used during verification.
