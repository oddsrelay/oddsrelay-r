test_that("a call sends the key, gzip and filters, and returns the body with its headers", {
  fresh_cache()
  withr::local_envvar(ODDSRELAY_KEY = "test-key-value\n")
  api <- mock_api(fixture_response("v2-odds-type.standard_filtered.json", headers = list(
    ETag = "\"c1-2\"", `X-Tokens-Cost` = "3", `X-Tokens-Remaining` = "unlimited",
    `X-Tokens-Reset` = "2026-10-01T00:00:00Z", `X-RateLimit-Remaining` = "9",
    `X-OddsRelay-Request-Id` = "or_req_00000000000000000000000000000000"
  )))

  board <- or_odds("standard", region = "uk", sports = c("soccer", "tennis"), odds_format = "decimal")

  req <- api$requests[[1]]
  expect_equal(auth_header(req), "Bearer test-key-value")
  expect_equal(req$options$accept_encoding, "gzip")
  url <- httr2::url_parse(req$url)
  expect_equal(url$path, "/v2/odds/standard")
  expect_equal(url$query, list(region = "uk", sports = "soccer,tennis", oddsFormat = "decimal"))
  expect_false(grepl("test-key-value", req$url, fixed = TRUE))
  expect_false(any(grepl("test-key-value", capture.output(print(req)), fixed = TRUE)))

  expect_s3_class(board$data, "data.frame")
  expect_equal(board$data$event_id, "or_evt_917dd44bce05")
  expect_equal(attr(board, "tokens")$cost, 3)
  expect_equal(attr(board, "tokens")$remaining, "unlimited")
  expect_equal(attr(board, "tokens")$reset, "2026-10-01T00:00:00Z")
  expect_true(is.na(attr(board, "tokens")$used))
  expect_equal(attr(board, "rate_limit")$remaining, 9)
  expect_equal(attr(board, "request_id"), "or_req_00000000000000000000000000000000")
  expect_false(attr(board, "not_modified"))
})

test_that("the .key argument wins over the environment, and no key means no header", {
  fresh_cache()
  withr::local_envvar(ODDSRELAY_KEY = "from-env")
  api <- mock_api(fixture_response("v2-usage.usage.json"), fixture_response("v2-status.status.json"))
  or_usage(.key = "from-arg")
  or_status()
  expect_equal(auth_header(api$requests[[1]]), "Bearer from-arg")
  expect_null(auth_header(api$requests[[2]]))
})

test_that("filters are written the way the API reads them", {
  moment <- as.POSIXct("2026-10-08 21:30:00", tz = "Europe/London")
  expect_equal(
    query_params(list(include_links = TRUE, limit = 100000, commenceTimeFrom = moment, cursor = NULL)),
    list(includeLinks = "true", limit = "100000", commenceTimeFrom = "2026-10-08T20:30:00Z")
  )
  expect_error(query_params(list("tennis")), "needs a name")
})

test_that("a key passed under the wrong name never reaches a URL", {
  fresh_cache()
  withr::local_envvar(ODDSRELAY_KEY = "")
  api <- mock_api(fixture_response("v2-status.status.json"))
  or_status(.key = "wrong-place-secret") # keyless route: accepted, never sent
  expect_false(grepl("wrong-place-secret", api$requests[[1]]$url, fixed = TRUE))
  expect_null(auth_header(api$requests[[1]]))

  for (call in list(
    function() or_odds("standard", key = "wrong-place-secret"),
    function() or_coverage(api_key = "wrong-place-secret"),
    function() or_raw(.Key = "wrong-place-secret")
  )) {
    msg <- tryCatch(call(), error = conditionMessage)
    expect_match(msg, "nothing was sent")
    expect_no_match(msg, "wrong-place-secret")
  }
  expect_length(api$requests, 1)
})

test_that("a printed result shows the body and one line of tokens, not the attributes", {
  fresh_cache()
  mock_api(fixture_response("v2-status.status.json", headers = list(`X-Tokens-Cost` = "0")))
  status <- or_status()
  out <- capture.output(print(status))
  expect_false(any(grepl("attr(", out, fixed = TRUE)))
  expect_equal(out[length(out)], "# tokens: cost 0")
  expect_s3_class(status, "oddsrelay_result")
  expect_false(inherits(unclass(status), "oddsrelay_result"))
})

test_that("a key an HTTP header cannot carry is refused without echoing it", {
  expect_error(or_usage(.key = "abc def-secret"), "copy it again")
  expect_no_match(tryCatch(or_usage(.key = "abc def-secret"), error = conditionMessage), "secret")
})

test_that("an unchanged reply comes back as not modified, from the cache, spending no tokens", {
  fresh_cache()
  withr::local_envvar(ODDSRELAY_KEY = "test-key")
  api <- mock_api(
    fixture_response("v2-sports.page.json", headers = list(ETag = "\"c0a1b2c3d-4\"")),
    httr2::response(304, headers = list(ETag = "\"c0a1b2c3d-4\"", `X-Tokens-Cost` = "0"))
  )
  first <- or_sports(region = "uk")
  second <- or_sports(region = "uk")

  expect_null(httr2::req_get_headers(api$requests[[1]])$`If-None-Match`)
  expect_equal(httr2::req_get_headers(api$requests[[2]])$`If-None-Match`, "\"c0a1b2c3d-4\"")
  expect_true(attr(second, "not_modified"))
  expect_equal(attr(second, "tokens")$cost, 0)
  expect_equal(second$data, first$data)
})

test_that("a 429 waits Retry-After and tries again, three requests in all", {
  fresh_cache()
  waits <- c()
  local_mocked_bindings(wait = function(seconds) waits <<- c(waits, seconds))
  busy <- fixture_response("error-429.too_many_requests.json", 429L, list(`Retry-After` = "2"))

  api <- mock_api(busy, busy, fixture_response("v2-status.status.json"))
  expect_equal(suppressMessages(or_status())$products$raw, "ok")
  expect_equal(waits, c(2, 2))

  waits <- c()
  api <- mock_api(busy, busy, busy, fixture_response("v2-status.status.json"))
  cnd <- suppressMessages(expect_error(or_status(), class = "oddsrelay_too_many_requests"))
  expect_s3_class(cnd, "oddsrelay_http_429")
  expect_equal(cnd$retry_after, 2)
  expect_length(api$requests, 3)
  expect_equal(waits, c(2, 2))

  waits <- c() # no Retry-After: one second, and the wait is announced
  mock_api(httr2::response(429), fixture_response("v2-status.status.json"))
  expect_message(or_status(), "trying again in 1 s")
  expect_equal(waits, 1)
})

test_that("a 402 carries cost, remaining and resets_at", {
  fresh_cache()
  mock_api(fixture_response("error-402.insufficient_tokens.json", 402L, list(`X-Tokens-Remaining` = "0")))
  cnd <- expect_error(or_raw(region = "uk", .key = "test-key"), class = "oddsrelay_insufficient_tokens")
  expect_s3_class(cnd, "oddsrelay_http_402")
  expect_s3_class(cnd, "oddsrelay_error")
  expect_equal(cnd$cost, 0)
  expect_equal(cnd$remaining, 0)
  expect_equal(cnd$resets_at, "2026-10-01T00:00:00Z")
  expect_equal(cnd$request_id, "or_req_00000000000000000000000000000000")
  expect_equal(cnd$tokens$remaining, 0)
})

test_that("every refusal is classed by its code and keeps the request id", {
  fresh_cache()
  cases <- list(
    list("error-400.unknown_sport.json", 400L, "oddsrelay_unknown_sport"),
    list("error-401.missing_api_key.json", 401L, "oddsrelay_missing_api_key"),
    list("error-403.sport_not_in_plan.json", 403L, "oddsrelay_sport_not_in_plan"),
    list("error-404.unknown_event.json", 404L, "oddsrelay_unknown_event"),
    list("error-503.temporarily_unavailable.json", 503L, "oddsrelay_temporarily_unavailable")
  )
  for (case in cases) {
    mock_api(fixture_response(case[[1]], case[[2]]))
    cnd <- expect_error(or_event("or_evt_1", .key = "test-key"), class = case[[3]])
    expect_s3_class(cnd, paste0("oddsrelay_http_", case[[2]]))
    expect_equal(cnd$status, case[[2]])
    expect_equal(cnd$request_id, "or_req_00000000000000000000000000000000")
    expect_match(conditionMessage(cnd), "request_id or_req_0")
  }
  expect_equal(cnd$error$code, "temporarily_unavailable")

  mock_api(fixture_response("error-400.unknown_sport.json", 400L))
  cnd <- expect_error(or_events("curling_xyz", .key = "test-key"), class = "oddsrelay_unknown_sport")
  expect_equal(cnd$error$valid[[1]], "american_football")
})

test_that("a refusal with no body still signals a classed condition", {
  fresh_cache()
  mock_api(httr2::response(502))
  cnd <- expect_error(or_status(), class = "oddsrelay_http_502")
  expect_null(cnd$code)
  expect_match(conditionMessage(cnd), "HTTP 502")

  mock_api(httr2::response(503, headers = list(`X-OddsRelay-Request-Id` = "or_req_11111111111111111111111111111111")))
  cnd <- expect_error(or_status(), class = "oddsrelay_http_503")
  expect_equal(cnd$request_id, "or_req_11111111111111111111111111111111")
})

test_that("a plain-text refusal is told by its first line", {
  fresh_cache()
  mock_api(httr2::response(503, headers = list(`Content-Type` = "text/plain; charset=utf-8"),
    body = charToRaw("warming\nsecond line\n")))
  cnd <- expect_error(or_healthz(), class = "oddsrelay_http_503")
  expect_match(conditionMessage(cnd), "HTTP 503: warming")
  expect_no_match(conditionMessage(cnd), "second line")
})

test_that("a 401 without a key says where the key goes", {
  fresh_cache()
  withr::local_envvar(ODDSRELAY_KEY = "")
  mock_api(fixture_response("error-401.missing_api_key.json", 401L))
  expect_error(or_usage(), "ODDSRELAY_KEY", class = "oddsrelay_missing_api_key")
})

test_that("the key never reaches a condition, even when a reply echoes it", {
  fresh_cache()
  echoed <- httr2::response(400, headers = list(`Content-Type` = "application/json"),
    body = charToRaw('{"error":{"code":"bad_request","message":"bad key echo-secret-123"}}'))
  mock_api(echoed)
  cnd <- expect_error(or_usage(.key = "echo-secret-123"), class = "oddsrelay_bad_request")
  expect_no_match(conditionMessage(cnd), "echo-secret-123")
  expect_no_match(cnd$error$message, "echo-secret-123")
})
