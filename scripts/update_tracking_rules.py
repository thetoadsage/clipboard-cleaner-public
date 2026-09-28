#!/usr/bin/env python3
"""
Maintainer-only tool. NOT run by the app, NOT called at build time.

Fetches the ClearURLs rule catalog (github.com/ClearURLs/Rules, LGPL-3.0),
keeps only the parts relevant to local, automatic query-parameter removal
(the `rules` arrays, plus the special "globalRules" provider), and writes a
compact resource file in this project's own schema:

    Sources/ClipboardCleanerCore/Resources/tracking-rules.json

Deliberately dropped from the upstream data: `rawRules` (regex over the
whole URL), `redirections`/`forceRedirection` (unwrap embedded URLs -- a
different feature), `completeProvider` (block a URL outright), `exceptions`
(skip-lists for things like login pages), and `referralMarketing` (params
like bare `ref`/`referrer` that ClearURLs itself treats as optional/off by
default, since they're often legitimate).

Run this occasionally by hand to refresh the catalog:

    python3 scripts/update_tracking_rules.py

It requires network access; the generated JSON is committed to the repo and
is the only thing the app reads at runtime.
"""
from __future__ import annotations

import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

COMMIT_API_URL = "https://api.github.com/repos/ClearURLs/Rules/commits/master"
RULES_URL_TEMPLATE = "https://raw.githubusercontent.com/ClearURLs/Rules/{sha}/data.min.json"
EXPECTED_SKIPPED_PROVIDERS = {"weibo"}

# Hand-maintained, NOT derived from ClearURLs -- a small number of
# well-known, unambiguous global tracking parameters not yet present in the
# upstream catalog as of this writing (e.g. Google Ads' newer click-id
# params, siblings of the already-covered `gclid`). Kept separate from the
# fetched data so provenance/attribution stays unambiguous. Extend
# sparingly and only for parameters that are safe to strip on any domain.
LOCAL_GLOBAL_ADDITIONS = ["wbraid", "gbraid", "gclsrc"]
# Hand-maintained, site-specific rules for parameters that are unambiguous
# tracking/share noise on a reviewed domain but unsafe to remove globally.
LOCAL_DOMAIN_ADDITIONS = {
    "z-lib.gd": ["dsource"],
}
OUTPUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "Sources"
    / "ClipboardCleanerCore"
    / "Resources"
    / "tracking-rules.json"
)

DOMAIN_TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9\-]*(?:\\?\.[a-z0-9][a-z0-9\-]*)+", re.IGNORECASE)
WILDCARD_TLD_RE = re.compile(r"([a-z0-9\-]+)\(\?:\\\.\[a-z\]\{2,\}\)\{1,\}")
PARAM_PREFIX_RE = re.compile(r"^\(\?:%3F\)\?")


def resolve_wildcard_base(url_pattern: str) -> str | None:
    """If `url_pattern` uses ClearURLs' "word(?:\\.[a-z]{2,}){1,}" multi-TLD
    idiom (e.g. "amazon(?:\\.[a-z]{2,}){1,}", matching amazon.com,
    amazon.co.uk, amazon.us, ...), returns the base word ("amazon"). The app
    matches this generically at runtime (see HostMatching.WildcardBase)
    instead of this script trying to enumerate every real-world TLD -- an
    enumerated list is inherently incomplete (this is the bug being fixed:
    aliexpress.us was silently unmatched because "us" wasn't on the list)."""
    match = WILDCARD_TLD_RE.search(url_pattern)
    return match.group(1) if match else None


def resolve_literal_domains(url_pattern: str) -> list[str]:
    """Best-effort extraction of literal, fixed-TLD domain(s) a provider's
    urlPattern matches (e.g. "facebook\\.com", or an alternation like
    "(youtube\\.com|youtu\\.be)"). Not a regex engine -- just this one shape."""
    tokens = DOMAIN_TOKEN_RE.findall(url_pattern)
    domains = []
    for token in tokens:
        cleaned = token.replace("\\.", ".").lower()
        if cleaned not in domains:
            domains.append(cleaned)
    return domains


def clean_rule_pattern(pattern: str) -> str:
    """Strip the `(?:%3F)?` prefix ClearURLs uses for its raw-query-string
    matching; irrelevant here since we only match against parsed query item
    names, which never contain that literal."""
    return PARAM_PREFIX_RE.sub("", pattern)


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": "clipboard-cleaner-rule-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read())


def fetch_pinned_upstream() -> tuple[str, dict]:
    """Resolve master once, then fetch rules from that immutable commit."""
    commit = fetch_json(COMMIT_API_URL)
    commit_sha = commit.get("sha") if isinstance(commit, dict) else None
    if not isinstance(commit_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", commit_sha):
        raise ValueError("ClearURLs commit API returned no valid 40-character SHA")

    rules_url = RULES_URL_TEMPLATE.format(sha=commit_sha)
    print(f"Fetching {rules_url} ...")
    return commit_sha, fetch_json(rules_url)


def validate_upstream_schema(data: object) -> dict:
    if not isinstance(data, dict) or set(data) != {"providers"}:
        raise ValueError("unexpected ClearURLs top-level schema; expected only 'providers'")
    providers = data["providers"]
    if not isinstance(providers, dict) or not providers:
        raise ValueError("ClearURLs 'providers' must be a non-empty object")

    for name, provider in providers.items():
        if not isinstance(name, str) or not isinstance(provider, dict):
            raise ValueError("every ClearURLs provider must be a named object")
        rules = provider.get("rules", [])
        if not isinstance(rules, list) or not all(isinstance(rule, str) for rule in rules):
            raise ValueError(f"provider {name!r} has a non-string 'rules' array")
        if rules and name != "globalRules" and not isinstance(provider.get("urlPattern"), str):
            raise ValueError(f"provider {name!r} has rules but no string 'urlPattern'")
        if "completeProvider" in provider and not isinstance(provider["completeProvider"], bool):
            raise ValueError(f"provider {name!r} has a non-boolean 'completeProvider'")

    return providers


def main() -> int:
    commit_sha, data = fetch_pinned_upstream()
    providers = validate_upstream_schema(data)

    global_rules: list[str] = []
    domain_rules: dict[str, list[str]] = {}
    wildcard_domain_rules: dict[str, list[str]] = {}
    skipped: list[str] = []

    for name, provider in providers.items():
        rules = provider.get("rules") or []
        if not rules:
            continue

        cleaned_rules = [clean_rule_pattern(r) for r in rules]

        if name == "globalRules":
            global_rules = cleaned_rules
            continue

        if provider.get("completeProvider"):
            continue

        wildcard_base = resolve_wildcard_base(provider["urlPattern"])
        if wildcard_base:
            existing = wildcard_domain_rules.setdefault(wildcard_base, [])
            for rule in cleaned_rules:
                if rule not in existing:
                    existing.append(rule)
            continue

        domains = resolve_literal_domains(provider["urlPattern"])
        if not domains:
            skipped.append(name)
            continue

        for domain in domains:
            existing = domain_rules.setdefault(domain, [])
            for rule in cleaned_rules:
                if rule not in existing:
                    existing.append(rule)

    skipped_set = set(skipped)
    if skipped_set != EXPECTED_SKIPPED_PROVIDERS:
        raise ValueError(
            "unexpected set of skipped providers: "
            f"expected {sorted(EXPECTED_SKIPPED_PROVIDERS)}, got {sorted(skipped_set)}"
        )

    for domain, additions in LOCAL_DOMAIN_ADDITIONS.items():
        existing = domain_rules.setdefault(domain, [])
        for rule in additions:
            if rule not in existing:
                existing.append(rule)

    output = {
        "source": "Derived from ClearURLs/Rules (https://github.com/ClearURLs/Rules), LGPL-3.0",
        "sourceCommit": commit_sha,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "global": global_rules,
        "localGlobalAdditionsNote": (
            "Hand-maintained entries below are NOT derived from ClearURLs; "
            "see LOCAL_GLOBAL_ADDITIONS in scripts/update_tracking_rules.py."
        ),
        "localGlobalAdditions": LOCAL_GLOBAL_ADDITIONS,
        "localDomainAdditionsNote": (
            "Hand-maintained entries below are NOT derived from ClearURLs; "
            "they are reviewed for the named domain only."
        ),
        "localDomainAdditions": LOCAL_DOMAIN_ADDITIONS,
        "domains": dict(sorted(domain_rules.items())),
        "wildcardTLDDomainsNote": (
            "Keys are base labels (e.g. \"amazon\"), matched at runtime "
            "against any subdomain and any TLD chain of 2+ letter labels "
            "(amazon.com, amazon.co.uk, amazon.us, ...) -- see "
            "HostMatching.WildcardBase in the Swift source. Not an "
            "enumerated TLD list, so no supported country/TLD variant is "
            "silently missed."
        ),
        "wildcardTLDDomains": dict(sorted(wildcard_domain_rules.items())),
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n")

    print(f"Wrote {OUTPUT_PATH}")
    print(f"  global rules: {len(global_rules)}")
    print(f"  domains: {len(domain_rules)}")
    print(f"  wildcard-TLD domains: {len(wildcard_domain_rules)} ({', '.join(sorted(wildcard_domain_rules))})")
    if skipped:
        print(f"  skipped providers (no resolvable domain): {', '.join(sorted(skipped))}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
