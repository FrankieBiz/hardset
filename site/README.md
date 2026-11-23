# Hardset static site

Three public pages and one stylesheet. Plain HTML and CSS only: no framework, no
build step, no JavaScript, no analytics, no cookies, no external fonts, and no
requests to any third party.

| File | Purpose |
| --- | --- |
| `index.html` | Landing and marketing page |
| `privacy.html` | Privacy policy |
| `support.html` | Support and troubleshooting |
| `styles.css` | The whole site's styling |

The copy is grounded in `docs/release/PRIVACY_POLICY_DRAFT.md` and
`docs/release/SUPPORT_DRAFT.md`, corrected against the shipped code: local-only
storage, no account, no server, the CSV/JSON/SQLite exports and the JSON/CSV
restore path, the Lifetime unlock and its limits, and the fact that deleting the
app deletes local history. Health is written for the 1.0 decision that removes
Apple Health (D25). See `docs/release/APP-STORE-METADATA.md` for the one code
fact that must match that decision before submission.

## Preview locally

```bash
python3 -m http.server 8000 --directory site
```

Open `http://localhost:8000/`, then check 360 px and 1440 px wide with no
horizontal scroll, keyboard focus visible on every link, and the policy and
support pages reachable from every page.

## Publish (GitHub Pages, the default)

**Publishing waits for the owner.** Do not create the repository, enable Pages,
or point a domain at this site until Frankie approves the host, the domain, and
the final copy. The site copy is ready for that review; the release decision and
the Apple Health gate in `APP-STORE-METADATA.md` §9.1 are not.

A dedicated repository keeps the site separate from the app source and from the
developer's WebGL portfolio, which is decision D6. GitHub Pages serves a project
site at `https://<account>.github.io/<repo>/`; every link here is relative, so it
works at that path or at a custom domain root.

1. Decide the host and, if any, the custom domain. Record the decision in the
   launch notes. The default is a public GitHub repository named `hardset-site`
   owned by `FrankieBiz`.
2. Create the empty public repository (no README, no license) and clone it.
3. Copy the four **public** files to the repository root: `index.html`,
   `privacy.html`, `support.html` and `styles.css`. Do not copy the `site/` folder,
   and do not publish this `README.md`: it is the operator's checklist, not site
   content.
4. Commit and push to `main`. Use the repository's normal commit identity.
5. In the repository: **Settings → Pages → Build and deployment**. Set
   **Source** to **Deploy from a branch**, **Branch** to `main`, **Folder** to
   `/ (root)`, and save.
6. Wait for the deployment to finish. The URL is shown on the Pages settings
   page, for example `https://frankiebiz.github.io/hardset-site/`.
7. Open `/`, `/privacy.html` and `/support.html` on the published site. Confirm
   all three load over HTTPS, the relative links work, and the pages still read
   at 360 px and 1440 px with no horizontal scroll.
8. Optional custom domain: add a file named `CNAME` at the repository root
   containing only the domain (for example `hardset.app`), configure the DNS
   records GitHub documents for that domain, then enable **Enforce HTTPS** in
   Pages settings. Do not add `CNAME` before the domain exists.
9. Put the final URLs into App Store Connect and into
   `docs/release/APP-STORE-METADATA.md`:
   - Marketing URL: the site root.
   - Support URL: `<site>/support.html`.
   - Privacy Policy URL: `<site>/privacy.html`.
10. Re-check the published pages after any edit. There is no cache-busting step;
    GitHub Pages serves the new commit after its deployment finishes.

If the owner prefers a different static host, the same four files work unchanged.
Keep the paths `privacy.html` and `support.html`, or update both the links in the
pages and the URLs in App Store Connect.

## Before publishing

- Confirm the operator line: Frankie Bisignano, frankabisignano@gmail.com.
- Confirm the "last updated" date on the privacy page (currently 23 November
  2026).
- Confirm the price wording: free download; $19.99 launch and $29.99 standing
  for the optional Lifetime unlock (D17).
- Confirm the 1.0 build removes Apple Health (D25) before the privacy and support
  pages claim it does. The current branch still links HealthKit; see the
  verification note in `docs/release/APP-STORE-METADATA.md`.
