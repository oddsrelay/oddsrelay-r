test_that("each function reads its own route", {
  withr::local_envvar(ODDSRELAY_KEY = "test-key")
  routes <- list(
    list(function() or_odds("each-way"), "/v2/odds/each-way", "v2-odds-type.standard_filtered.json"),
    list(function() or_raw(cursor = "abc"), "/v2/odds/raw", "v2-odds-raw.page.json"),
    list(function() or_event("or_evt 1/2"), "/v2/odds/event/or_evt%201%2F2", "v2-odds-event-id.event.json"),
    list(function() or_sports(), "/v2/sports", "v2-sports.page.json"),
    list(function() or_events("tennis"), "/v2/events", "v2-events.page.json"),
    list(function() or_bookmakers(), "/v2/bookmakers", "v2-bookmakers.catalogue.json"),
    list(function() or_regions(), "/v2/regions", "v2-regions.regions.json"),
    list(function() or_coverage(region = "uk"), "/v2/coverage", "v2-coverage.keyless.json"),
    list(function() or_status(), "/v2/status", "v2-status.status.json"),
    list(function() or_health(), "/v2/health", "v2-health.health.json"),
    list(function() or_usage(), "/v2/usage", "v2-usage.usage.json"),
    list(function() or_pricing(), "/v2/pricing", "v2-pricing.table.json"),
    list(function() or_healthz(), "/healthz", "healthz.txt")
  )
  for (route in routes) {
    fresh_cache()
    api <- mock_api(fixture_response(route[[3]]))
    result <- route[[1]]()
    expect_equal(httr2::url_parse(api$requests[[1]]$url)$path, route[[2]])
    expect_false(is.null(attr(result, "tokens")))
  }
})

test_that("or_events sends the sport it is given", {
  fresh_cache()
  api <- mock_api(fixture_response("v2-events.page.json"))
  events <- or_events("tennis", region = "uk", .key = "test-key")
  expect_equal(httr2::url_parse(api$requests[[1]]$url)$query, list(sport = "tennis", region = "uk"))
  expect_s3_class(events$data, "data.frame")
  expect_false(is.null(events$meta$next_cursor))
})

test_that("a quote is a small list", {
  fresh_cache()
  api <- mock_api(fixture_response("v2-odds-type.quote.json"))
  quote <- or_odds("standard", region = "uk", quote = TRUE, .key = "test-key")
  expect_equal(httr2::url_parse(api$requests[[1]]$url)$query$quote, "true")
  expect_equal(quote$cost, 0)
  expect_equal(quote$remaining, "unlimited")
})

test_that("or_healthz returns text and or_openapi keeps the description's structure", {
  fresh_cache()
  mock_api(
    fixture_response("healthz.txt"),
    httr2::response(200, headers = list(`Content-Type` = "application/json"),
      body = charToRaw('{"openapi":"3.1.0","info":{"version":"2026-07-08"},"tags":[{"name":"odds"}]}'))
  )
  text <- or_healthz() # assigned first: expect_match() evaluates its argument twice
  expect_match(text, "^ok")
  spec <- or_openapi()
  expect_equal(spec$info$version, "2026-07-08")
  expect_type(spec$tags, "list")
})
