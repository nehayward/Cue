#!/usr/bin/python3
"""Show or change what the paywall says about a sale, without RevenueCat's
website. The paywall reads three keys from the metadata of RevenueCat's
current offering (`Offering.saleHeadline`, `saleBadge`, `saleBadgePlan` in
Cue/Paywall/PurchaseFooter.swift), and every copy of Cue picks a change up the
next time its paywall opens:

  Scripts/paywall-sale.py                                  what it says now
  Scripts/paywall-sale.py --badge "50% OFF" --plan monthly a badge on Monthly,
                                                           chosen when it opens
  Scripts/paywall-sale.py --headline "Half off Monthly."   the paywall's title
  Scripts/paywall-sale.py --headline ""                    back to the usual title
  Scripts/paywall-sale.py --clear                          the sale over

--plan is monthly, yearly (or annual) or lifetime; yearly when left out.

The wording is all this changes. The price a badge promises has to be set in
App Store Connect: an introductory offer on a subscription, or a scheduled
price on Lifetime.

Needs RevenueCat's v2 secret key in .secrets/revenuecat.env (RC_SECRET_KEY=…)
or REVENUECAT_SECRET_KEY.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

PROJECT = "proj9275768e"
OFFERING = "default"
KEYS = ("headline", "badge", "badge_plan")
PLANS = {"monthly": "monthly", "yearly": "annual", "annual": "annual", "lifetime": "lifetime"}


def secret_key():
    if os.environ.get("REVENUECAT_SECRET_KEY"):
        return os.environ["REVENUECAT_SECRET_KEY"]
    path = os.path.join(os.path.dirname(__file__), "..", ".secrets", "revenuecat.env")
    try:
        for line in open(path):
            name, _, value = line.strip().partition("=")
            if name == "RC_SECRET_KEY" and value:
                return value
    except FileNotFoundError:
        pass
    sys.exit("No RevenueCat secret key: put RC_SECRET_KEY=sk_… in .secrets/revenuecat.env.")


def call(method, path, body=None):
    request = urllib.request.Request(
        f"https://api.revenuecat.com/v2/projects/{PROJECT}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"Bearer {secret_key()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = json.load(error).get("message", "") if error.headers.get("Content-Type", "").startswith("application/json") else ""
        sys.exit(f"RevenueCat said {error.code}: {detail}")


def show(metadata):
    sale = {key: metadata[key] for key in KEYS if key in metadata}
    if not sale:
        print("No sale: the paywall shows its usual title and badges.")
        return
    print(f"Headline: {sale.get('headline', '(the usual title)')}")
    if "badge" in sale:
        plan = sale.get("badge_plan", "annual")
        print(f"Badge:    {sale['badge']}  on {'yearly' if plan == 'annual' else plan}, the only badge, chosen when the paywall opens")
    others = {key: value for key, value in metadata.items() if key not in KEYS}
    if others:
        print(f"Other metadata, left as it is: {json.dumps(others)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--badge", help='a badge, e.g. "50%% OFF" ("" removes it)')
    parser.add_argument("--plan", help="the plan the badge goes on: monthly, yearly or lifetime")
    parser.add_argument("--headline", help='the paywall\'s title ("" for the usual one)')
    parser.add_argument("--clear", action="store_true", help="remove the headline and badge")
    args = parser.parse_args()

    offering = next((o for o in call("GET", "/offerings")["items"] if o["lookup_key"] == OFFERING), None)
    if not offering:
        sys.exit(f"RevenueCat has no offering called {OFFERING}.")
    metadata = dict(offering.get("metadata") or {})

    if not (args.clear or args.badge is not None or args.plan or args.headline is not None):
        show(metadata)
        return

    if args.clear:
        for key in KEYS:
            metadata.pop(key, None)
    if args.headline is not None:
        if args.headline.strip():
            metadata["headline"] = args.headline.strip()
        else:
            metadata.pop("headline", None)
    if args.badge is not None:
        if args.badge.strip():
            metadata["badge"] = args.badge.strip()
        else:
            metadata.pop("badge", None)
            metadata.pop("badge_plan", None)
    if args.plan:
        plan = PLANS.get(args.plan.lower())
        if not plan:
            sys.exit("--plan is monthly, yearly or lifetime.")
        if "badge" not in metadata:
            sys.exit("--plan says which plan the badge goes on; give a --badge too.")
        metadata["badge_plan"] = plan

    updated = call("POST", f"/offerings/{offering['id']}", {"metadata": metadata})
    show(updated.get("metadata") or {})


if __name__ == "__main__":
    main()
