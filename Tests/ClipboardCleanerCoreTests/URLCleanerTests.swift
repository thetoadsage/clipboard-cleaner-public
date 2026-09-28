import Testing

@testable import ClipboardCleanerCore

struct URLCleanerTests {

    // MARK: - Non-URL text

    @Test func plainTextIsUnchanged() {
        let text = "just some regular text, not a link"
        #expect(URLCleaner.clean(text) == text)
    }

    @Test func emptyStringIsUnchanged() {
        #expect(URLCleaner.clean("") == "")
    }

    @Test func nonHTTPSchemeIsUnchanged() {
        let text = "mailto:someone@example.com?utm_source=newsletter"
        #expect(URLCleaner.clean(text) == text)
    }

    @Test func textThatLooksLikeAFilePathIsUnchanged() {
        let text = "/usr/local/bin/foo?utm_source=bar"
        #expect(URLCleaner.clean(text) == text)
    }

    // MARK: - URLs with no query params

    @Test func plainURLWithoutQueryIsUnchanged() {
        let text = "https://www.example.com/path/to/page"
        #expect(URLCleaner.clean(text) == text)
    }

    @Test func urlWithOnlyFragmentIsUnchanged() {
        let text = "https://example.com/page#section-2"
        #expect(URLCleaner.clean(text) == text)
    }

    // MARK: - Tracking parameter removal

    @Test func removesSingleUTMParameter() {
        let input = "https://example.com/article?utm_source=twitter"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func removesAllCommonUTMParameters() {
        let input =
            "https://example.com/article?utm_source=a&utm_medium=b&utm_campaign=c&utm_term=d&utm_content=e"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test(
        arguments: [
            ("https://example.com/?gclid=abc123", "https://example.com/"),
            ("https://example.com/?fbclid=abc123", "https://example.com/"),
            ("https://example.com/?msclkid=abc123", "https://example.com/"),
            ("https://example.com/?mc_cid=abc&mc_eid=def", "https://example.com/"),
        ]
    )
    func removesNonUTMTrackingParameters(input: String, expected: String) {
        #expect(URLCleaner.clean(input) == expected)
    }

    // `igshid` is only known as tracking on Instagram, not globally, so it
    // belongs here rather than in the generic example.com cases above.
    @Test func removesIgshidOnInstagramButPreservesItElsewhere() {
        #expect(URLCleaner.clean("https://instagram.com/p/abc/?igshid=abc123") == "https://instagram.com/p/abc/")
        let unrelated = "https://example.com/?igshid=abc123"
        #expect(URLCleaner.clean(unrelated) == unrelated)
    }

    @Test func trackingParameterMatchingIsCaseInsensitive() {
        let input = "https://example.com/article?UTM_Source=twitter&Utm_Campaign=spring"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func preservesLegitimateParametersWhileRemovingTracking() {
        let input = "https://example.com/search?q=swift&utm_source=google&page=2"
        let result = URLCleaner.clean(input)
        #expect(result == "https://example.com/search?q=swift&page=2")
    }

    @Test func preservesQueryOrderOfRemainingParameters() {
        let input = "https://example.com/?a=1&utm_source=x&b=2&fbclid=y&c=3"
        #expect(URLCleaner.clean(input) == "https://example.com/?a=1&b=2&c=3")
    }

    @Test func urlWithOnlyLegitimateParametersIsUnchanged() {
        let input = "https://example.com/search?q=swift&page=2"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func dropsQuestionMarkWhenAllParametersAreTracking() {
        let input = "https://example.com/page?utm_source=x&utm_medium=y"
        let result = URLCleaner.clean(input)
        #expect(!result.contains("?"))
        #expect(result == "https://example.com/page")
    }

    @Test func preservesFragmentWhenRemovingTrackingParameters() {
        let input = "https://example.com/page?utm_source=x&q=1#section"
        #expect(URLCleaner.clean(input) == "https://example.com/page?q=1#section")
    }

    @Test func handlesHTTPSchemeNotJustHTTPS() {
        let input = "http://example.com/page?utm_source=x&q=1"
        #expect(URLCleaner.clean(input) == "http://example.com/page?q=1")
    }

    // MARK: - YouTube `si` tracking parameter

    @Test func removesSiFromYoutuBeShareLink() {
        let input = "https://youtu.be/eMuYxfL6zYc?si=0-8wqsHsdslkcwYN"
        #expect(URLCleaner.clean(input) == "https://youtu.be/eMuYxfL6zYc")
    }

    @Test func removesSiFromYoutubeWatchURLButKeepsV() {
        let input = "https://www.youtube.com/watch?v=eMuYxfL6zYc&si=0-8wqsHsdslkcwYN"
        #expect(URLCleaner.clean(input) == "https://www.youtube.com/watch?v=eMuYxfL6zYc")
    }

    @Test func removesSiFromYoutubeURLButKeepsT() {
        let input = "https://youtu.be/eMuYxfL6zYc?si=0-8wqsHsdslkcwYN&t=42"
        #expect(URLCleaner.clean(input) == "https://youtu.be/eMuYxfL6zYc?t=42")
    }

    @Test func youtubeURLWithOnlyLegitimateParametersIsUnchanged() {
        let input = "https://www.youtube.com/watch?v=eMuYxfL6zYc&list=PL123&index=4&t=42"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func siIsPreservedOnNonYoutubeHosts() {
        let input = "https://example.com/page?si=some-session-id"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test(arguments: ["www.youtube.com", "m.youtube.com", "music.youtube.com"])
    func removesSiOnYoutubeSubdomains(host: String) {
        let input = "https://\(host)/watch?v=eMuYxfL6zYc&si=0-8wqsHsdslkcwYN"
        #expect(URLCleaner.clean(input) == "https://\(host)/watch?v=eMuYxfL6zYc")
    }

    // MARK: - Catalog-backed rules (ClearURLs-derived + local additions)

    @Test func removesGoogleAdsClickIdSiblings() {
        // wbraid/gbraid/gclsrc are hand-maintained local additions (not yet
        // in the upstream ClearURLs snapshot) -- see
        // scripts/update_tracking_rules.py.
        #expect(URLCleaner.clean("https://example.com/?wbraid=abc") == "https://example.com/")
        #expect(URLCleaner.clean("https://example.com/?gbraid=abc") == "https://example.com/")
        #expect(URLCleaner.clean("https://example.com/?gclsrc=aw") == "https://example.com/")
    }

    @Test func removesGoogleSearchOnlyParametersButPreservesQuery() {
        // "ved" and "gs_lcp" are Google-search-scoped in the catalog (regex
        // pattern "gs_[a-z]*"), not global -- exercises domain-scoped regex
        // rules, not just domain-scoped literal ones.
        let input = "https://www.google.com/search?q=swift&ved=abc&gs_lcp=xyz"
        #expect(URLCleaner.clean(input) == "https://www.google.com/search?q=swift")
    }

    @Test func googleSearchOnlyParametersArePreservedOnOtherHosts() {
        let input = "https://example.com/?ved=abc"
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Wildcard-TLD domain resolution (generic matching, not an
    // enumerated TLD list -- regression coverage for the bug where
    // aliexpress.us silently matched nothing because "us" wasn't on a
    // hand-written list of common TLDs)

    @Test func aliexpressUsMatchesAliexpressDomainScopedRules() {
        // Non-product path so this exercises the blocklist/domain-resolution
        // layer directly, not the AliExpress canonical URL rule.
        let input = "https://www.aliexpress.us/wholesale?ws_ab_test=abc&q=widget"
        #expect(URLCleaner.clean(input) == "https://www.aliexpress.us/wholesale?q=widget")
    }

    @Test func aliexpressComStillMatchesAliexpressDomainScopedRules() {
        let input = "https://www.aliexpress.com/wholesale?ws_ab_test=abc&q=widget"
        #expect(URLCleaner.clean(input) == "https://www.aliexpress.com/wholesale?q=widget")
    }

    @Test(arguments: ["aliexpress.us", "aliexpress.com", "aliexpress.co.uk", "aliexpress.de", "aliexpress.nl"])
    func aliexpressMatchesAcrossArbitraryTLDs(tld: String) {
        let input = "https://www.\(tld)/wholesale?ws_ab_test=abc"
        #expect(URLCleaner.clean(input) == "https://www.\(tld)/wholesale")
    }

    @Test func amazonUsMatchesAmazonDomainScopedRules() {
        // amazon.us isn't on any hand-written TLD list either; "qid" is an
        // amazon-search-scoped rule in the catalog.
        let input = "https://www.amazon.us/s?k=widget&qid=12345"
        #expect(URLCleaner.clean(input) == "https://www.amazon.us/s?k=widget")
    }

    @Test func ebayMatchesAcrossTLDsViaWildcardResolution() {
        let input = "https://www.ebay.us/itm/123456?_trksid=abc&hash=item123"
        #expect(URLCleaner.clean(input) == "https://www.ebay.us/itm/123456")
    }

    @Test func unrelatedDomainsDoNotMatchWildcardTLDRules() {
        // Must not match on substring alone -- "aliexpress" has to be a
        // full dot-separated label, not a prefix/suffix of some other label.
        let notAliExpress1 = "https://aliexpressgroup.com/wholesale?ws_ab_test=abc"
        #expect(URLCleaner.clean(notAliExpress1) == notAliExpress1)

        let notAliExpress2 = "https://evil-aliexpress.com/wholesale?ws_ab_test=abc"
        #expect(URLCleaner.clean(notAliExpress2) == notAliExpress2)

        let notAmazon = "https://amazon-reviews.example.com/?qid=12345"
        #expect(URLCleaner.clean(notAmazon) == notAmazon)
    }

    // MARK: - Canonical URL rules: AliExpress

    @Test func aliExpressProductURLIsReducedToCanonicalForm() {
        let input =
            "https://www.aliexpress.us/item/3256812635547747.html?sourceType=561&pvid=aa64d73d-d596-4c09-bb29-925c4817b3ff&pdp_ext_f=%7B%22ship_from%22:%22CN%22,%22sku_id%22:%2212000059455532136%22%7D&scm=1007.28480.478283.0&scm-url=1007.28480.478283.0&scm_id=1007.28480.478283.0&aecmd=true&gatewayAdapt=glo2usa"
        #expect(URLCleaner.clean(input) == "https://www.aliexpress.us/item/3256812635547747.html")
    }

    @Test(arguments: ["aliexpress.com", "aliexpress.us", "aliexpress.ru", "www.aliexpress.com"])
    func aliExpressCanonicalRuleAppliesOnReviewedDomainsAndSubdomains(host: String) {
        let input = "https://\(host)/item/123456.html?scm=1.2.3&sourceType=561"
        #expect(URLCleaner.clean(input) == "https://\(host)/item/123456.html")
    }

    @Test func aliExpressAlreadyCleanURLIsUnchanged() {
        let input = "https://www.aliexpress.us/item/3256812635547747.html"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func aliExpressNonProductPageFallsThroughToBlocklistOnly() {
        // Not a /item/<id>.html path, so the canonical rule must not apply --
        // only known tracking params (scm here) get stripped; an unknown
        // param (SearchText) must survive untouched. Uses .com (rather than
        // the .us TLD from the canonical-rule tests above) because the
        // ClearURLs-derived blocklist's domain list is TLD-enumerated and
        // doesn't include aliexpress.us -- a separate, pre-existing gap,
        // not something this test is meant to exercise.
        let input = "https://www.aliexpress.com/wholesale?SearchText=widget&scm=1.2.3"
        #expect(URLCleaner.clean(input) == "https://www.aliexpress.com/wholesale?SearchText=widget")
    }

    // MARK: - Canonical URL rules: Amazon

    @Test func amazonProductURLWithSlugAndRefIsReducedToCanonicalDpForm() {
        let input = "https://www.amazon.com/Anker-Charger-Fast-Charging-Adapter/dp/B08XYZ1234/ref=sr_1_3?crid=ABC&keywords=charger&qid=1699999999&sprefix=charger&sr=8-3"
        #expect(URLCleaner.clean(input) == "https://www.amazon.com/dp/B08XYZ1234")
    }

    @Test func amazonGpProductPathIsReducedToCanonicalDpForm() {
        let input = "https://www.amazon.co.uk/gp/product/B08XYZ1234?psc=1&th=1"
        #expect(URLCleaner.clean(input) == "https://www.amazon.co.uk/dp/B08XYZ1234")
    }

    @Test(arguments: ["amazon.cn", "amazon.ie", "amazon.co.za"])
    func additionalReviewedAmazonStorefrontsAreCanonicalized(host: String) {
        let input = "https://www.\(host)/Example-Product/dp/B08XYZ1234?ref=share&tag=tracking"
        #expect(URLCleaner.clean(input) == "https://www.\(host)/dp/B08XYZ1234")
    }

    @Test func amazonAlreadyCanonicalURLIsUnchanged() {
        let input = "https://www.amazon.com/dp/B08XYZ1234"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func amazonNonProductPageFallsThroughToBlocklistOnly() {
        // A search-results page, not a /dp/ product page -- the canonical
        // rule must not apply. The legitimate search keyword (k) must
        // survive; only recognized tracking params get removed.
        let input = "https://www.amazon.com/s?k=charger&utm_source=newsletter"
        #expect(URLCleaner.clean(input) == "https://www.amazon.com/s?k=charger")
    }

    @Test func unreviewedBrandLikeDomainsNeverTriggerWholeURLTransformations() {
        let destination = "https://example.com/private?token=keep"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let googleLookalike = "https://www.google.zip/url?q=\(encoded)&sa=t"
        let amazonLookalike = "https://amazon.example/dp/B08XYZ1234?checkoutToken=keep"
        let aliExpressLookalike = "https://aliexpress.example/item/123456.html?paymentToken=keep"

        #expect(URLCleaner.clean(googleLookalike) != destination)
        #expect(URLCleaner.clean(googleLookalike).contains("google.zip/url"))
        #expect(URLCleaner.clean(amazonLookalike) == amazonLookalike)
        #expect(URLCleaner.clean(aliExpressLookalike) == aliExpressLookalike)
    }

    @Test(
        arguments: [
            ("https://example.com/login?sessionToken=keep&utm_source=email", "https://example.com/login?sessionToken=keep"),
            ("https://example.com/checkout?cart=keep&utm_source=email", "https://example.com/checkout?cart=keep"),
            ("https://example.com/auth/callback?code=keep&utm_source=email", "https://example.com/auth/callback?code=keep"),
            ("https://example.com/payment?paymentToken=keep&utm_source=email", "https://example.com/payment?paymentToken=keep"),
            ("https://www.amazon.com/gp/cart/view.html?cartToken=keep&utm_source=email", "https://www.amazon.com/gp/cart/view.html?cartToken=keep"),
            ("https://www.aliexpress.com/p/payment?paymentToken=keep&utm_source=email", "https://www.aliexpress.com/p/payment?paymentToken=keep"),
            ("https://accounts.google.com/o/oauth2/auth?client_id=keep&utm_source=email", "https://accounts.google.com/o/oauth2/auth?client_id=keep"),
        ]
    )
    func sensitiveFlowsPreserveFunctionalParameters(input: String, expected: String) {
        #expect(URLCleaner.clean(input) == expected)
    }

    // MARK: - Canonical URL rules: Best Buy

    @Test func bestBuyProductURLWithSlugIsReducedToCanonicalForm() {
        let input = "https://www.bestbuy.com/site/apple-airpods-pro/6084400.p?skuId=6084400&ref=212&loc=1"
        #expect(URLCleaner.clean(input) == "https://www.bestbuy.com/site/6084400.p")
    }

    @Test func bestBuyProductURLWithoutSlugIsReducedToCanonicalForm() {
        let input = "https://www.bestbuy.com/site/6084400.p?skuId=6084400"
        #expect(URLCleaner.clean(input) == "https://www.bestbuy.com/site/6084400.p")
    }

    @Test func bestBuyNonProductPageFallsThroughToBlocklistOnly() {
        let input = "https://www.bestbuy.com/site/searchpage.jsp?st=airpods&utm_source=email"
        #expect(URLCleaner.clean(input) == "https://www.bestbuy.com/site/searchpage.jsp?st=airpods")
    }

    // MARK: - Canonical URL rules: Walmart

    @Test func walmartProductURLWithSlugIsReducedToCanonicalForm() {
        let input = "https://www.walmart.com/ip/Apple-AirPods-Pro/609174330?classType=REGULAR&athAsset=abc&athena=xyz"
        #expect(URLCleaner.clean(input) == "https://www.walmart.com/ip/609174330")
    }

    @Test func walmartProductURLWithoutSlugIsReducedToCanonicalForm() {
        let input = "https://www.walmart.com/ip/609174330?classType=REGULAR"
        #expect(URLCleaner.clean(input) == "https://www.walmart.com/ip/609174330")
    }

    @Test func walmartNonProductPageFallsThroughToBlocklistOnly() {
        let input = "https://www.walmart.com/search?q=airpods&utm_source=email"
        #expect(URLCleaner.clean(input) == "https://www.walmart.com/search?q=airpods")
    }

    // MARK: - Canonical URL rules: MakerWorld

    @Test func makerWorldModelURLDropsQueryAndFragment() {
        // The exact reported case: ?from=search + #profileId-... are removed,
        // the full locale+model path is preserved.
        let input = "https://makerworld.com/en/models/1085885-climbing-plant-clip?from=search#profileId-2763032"
        #expect(URLCleaner.clean(input) == "https://makerworld.com/en/models/1085885-climbing-plant-clip")
    }

    @Test func makerWorldModelURLWithDifferentLocaleIsSupported() {
        // A different locale segment is an intentionally-supported variation;
        // the model path is still preserved, query + fragment still dropped.
        let input = "https://makerworld.com/de/models/1234567-mein-modell?from=search&foo=bar#section"
        #expect(URLCleaner.clean(input) == "https://makerworld.com/de/models/1234567-mein-modell")
    }

    @Test func makerWorldNonModelPageIsNotStrippedByCanonicalRule() {
        // A non-model MakerWorld page must NOT match the canonical rule, so
        // its query and fragment are preserved (falling through to the
        // tracking blocklist, which strips nothing here: `from`/`keyword`
        // are not tracking parameters and fragments are never removed
        // globally).
        let input = "https://makerworld.com/en/search?keyword=clip&from=explore#top"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func nonMakerWorldURLWithFromAndFragmentIsUnchanged() {
        // `from` is deliberately not a global tracking parameter and
        // fragments are never removed globally, so an unrelated domain with
        // the same shape is left completely untouched.
        let input = "https://example.com/page?from=search#profileId-2763032"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func makerWorldModelURLWithoutLocaleOrSlugIsSupported() {
        // Locale segment and "-<slug>" suffix are both optional; the bare
        // "/models/<id>" shape is still a confident model-page match.
        let input = "https://makerworld.com/models/1085885?from=search#x"
        #expect(URLCleaner.clean(input) == "https://makerworld.com/models/1085885")
    }

    @Test func makerWorldLookalikePathDoesNotMatchCanonicalRule() {
        // Not a "/models/<digits>" path -- must fall through untouched
        // rather than being rewritten by the MakerWorld rule.
        let input = "https://makerworld.com/en/models?sort=trending#grid"
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Redirect unwrapping: Facebook

    @Test func unwrapsFacebookShareLink() {
        let destination = "https://example.com/article?id=42"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://l.facebook.com/l.php?u=\(encoded)&h=AT123abc"
        #expect(URLCleaner.clean(input) == destination)
    }

    @Test func unwrapsFacebookShareLinkAndThenCleansDestination() {
        let destination = "https://example.com/article?id=42&utm_source=facebook"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://l.facebook.com/l.php?u=\(encoded)&h=AT123abc"
        #expect(URLCleaner.clean(input) == "https://example.com/article?id=42")
    }

    @Test func plainFacebookURLsAreNotTreatedAsWrappers() {
        // Not on l.facebook.com / not /l.php -- must be unaffected by unwrap logic.
        let input = "https://www.facebook.com/someuser/posts/123456"
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Redirect unwrapping: Google

    @Test func unwrapsGoogleRedirectURLParameter() {
        let destination = "https://example.com/page"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://www.google.com/url?url=\(encoded)&sa=t"
        #expect(URLCleaner.clean(input) == destination)
    }

    @Test func unwrapsGoogleRedirectQParameter() {
        let destination = "https://example.com/page?utm_source=google"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://www.google.com/url?q=\(encoded)&sa=t&ved=abc"
        #expect(URLCleaner.clean(input) == "https://example.com/page")
    }

    @Test func plainGoogleSearchURLsAreNotTreatedAsWrappers() {
        // Path is /search, not /url -- the `q` parameter here is the actual
        // search query, not a redirect target, and must be preserved as-is.
        let input = "https://www.google.com/search?q=swift+programming"
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Redirect unwrapping: BusinessWire and href.li

    @Test func unwrapsBusinessWireRedirectAndThenCleansDestination() {
        let destination = "https://example.com/article?utm_source=businesswire"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://cts.businesswire.com/portal/site/home/?url=\(encoded)&newsId=123"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func unwrapsHrefLiRawQueryDestination() {
        let input = "https://href.li/?https://example.com/article?utm_source=share&fbclid=hrefli"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func unwrapsPercentEncodedHrefLiDestination() {
        let destination = "https://example.com/article?utm_source=share"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://href.li/?\(encoded)"
        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func hrefLiPreservesDestinationQueryEscapes() {
        // `%26` belongs inside the destination's `q` value. Decoding the
        // wrapper query before extraction would turn it into a new parameter.
        let input = "https://href.li/?https://example.com/search?q=a%26b"
        #expect(URLCleaner.clean(input) == "https://example.com/search?q=a%26b")
    }

    @Test func hrefLiPreservesUnescapedDestinationFragment() {
        let input = "https://href.li/?https://example.com/article#comments"
        #expect(URLCleaner.clean(input) == "https://example.com/article#comments")
    }

    @Test func unwrapsFullyPercentEncodedHrefLiDestination() {
        let destination = "https://example.com/article?ref=summer#comments"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let input = "https://href.li/?\(encoded)"
        #expect(URLCleaner.clean(input) == destination)
    }

    @Test func nonHTTPWrapperInputIsLeftUntouched() {
        let input = "ftp://www.google.com/url?q=https%3A%2F%2Fexample.com%2Farticle"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func wrapperLookalikesAndNonHTTPDestinationsAreUntouched() {
        let destination = "https://example.com/article"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let businessWireLookalike = "https://cts.businesswire.example/?url=\(encoded)"
        let hrefLiNonHTTP = "https://href.li/?javascript:alert(1)"

        #expect(URLCleaner.clean(businessWireLookalike) == businessWireLookalike)
        #expect(URLCleaner.clean(hrefLiNonHTTP) == hrefLiNonHTTP)
    }

    // MARK: - Functional query parameters must survive catalog updates

    @Test(
        arguments: [
            ("https://play.google.com/store/apps/details?id=com.example.app&utm_source=share", "https://play.google.com/store/apps/details?id=com.example.app"),
            ("https://www.macys.com/shop/product/example?ID=10920481&utm_source=share", "https://www.macys.com/shop/product/example?ID=10920481"),
            ("https://www.facebook.com/story.php?story_fbid=1&id=2&ref=share", "https://www.facebook.com/story.php?story_fbid=1&id=2"),
            ("https://www.lenovo.com/us/en/p/example?bundleId=123&utm_source=share", "https://www.lenovo.com/us/en/p/example?bundleId=123"),
            ("https://www.xiaohongshu.com/explore/abc?xsec_token=token&xsec_source=share", "https://www.xiaohongshu.com/explore/abc?xsec_token=token"),
            ("https://www.webtoons.com/en/example/viewer?title_no=1&episode_no=2&utm_source=share", "https://www.webtoons.com/en/example/viewer?title_no=1&episode_no=2"),
            ("https://weatherkit.apple.com/alert?lang=en&party=abc&ids=1&utm_source=share", "https://weatherkit.apple.com/alert?lang=en&party=abc&ids=1"),
            ("https://www.reddit.com/media?url=https%3A%2F%2Fexample.com%2Fimage.jpg&rdt=123", "https://www.reddit.com/media?url=https://example.com/image.jpg"),
        ]
    )
    func functionalParametersSurviveTrackingRemoval(input: String, expected: String) {
        #expect(URLCleaner.clean(input) == expected)
    }

    // MARK: - New layers don't change behavior for unrelated URLs

    @Test func genericSiteWithTrackingParamsIsUnaffectedByNewLayers() {
        let input = "https://example.com/page?utm_source=x&q=1"
        #expect(URLCleaner.clean(input) == "https://example.com/page?q=1")
    }

    @Test func youtubeBehaviorIsUnaffectedByNewLayers() {
        let input = "https://youtu.be/eMuYxfL6zYc?si=0-8wqsHsdslkcwYN&t=42"
        #expect(URLCleaner.clean(input) == "https://youtu.be/eMuYxfL6zYc?t=42")
    }

    // MARK: - isURL

    @Test func isURLRecognizesHTTPAndHTTPS() {
        #expect(URLCleaner.isURL("https://example.com"))
        #expect(URLCleaner.isURL("http://example.com"))
    }

    @Test func isURLRejectsPlainText() {
        #expect(!URLCleaner.isURL("hello world"))
        #expect(!URLCleaner.isURL("mailto:a@b.com"))
        #expect(!URLCleaner.isURL(""))
    }
}
