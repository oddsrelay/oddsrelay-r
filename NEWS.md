# oddsrelay 0.1.0

* First release. One function for each GET route of the OddsRelay API, from
  `or_odds()` and `or_raw()` to `or_usage()` and `or_healthz()`.
* The key comes from `ODDSRELAY_KEY` or a `.key` argument and travels only in
  the `Authorization` header.
* Replies are asked for gzip-compressed. Each URL's `ETag` is kept for the
  session, so an unchanged reply comes back as a 304 that spends no tokens,
  returned as the body you already had with `attr(x, "not_modified")` set to
  `TRUE`.
* A 429 is retried after its `Retry-After` seconds, three requests in all.
* Every refusal signals a condition classed by its error code and status,
  carrying `request_id`; a 402 also carries `cost`, `remaining` and
  `resets_at`.
* The token and rate limit headers ride on every result as attributes.
