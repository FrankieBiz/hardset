# Hardset static site

Four public pages and one stylesheet. Plain HTML and CSS only: no framework, no
build step, no JavaScript, no analytics, no cookies, no external fonts, and no
requests to any third party.

| File | Purpose |
| --- | --- |
| `index.html` | Landing and marketing page |
| `privacy.html` | Privacy policy |
| `support.html` | Support and troubleshooting |
| `changelog.html` | Release notes in user terms |
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

## Publish (GitHub Pages workflow)

Hosting is **GitHub Pages**, free, serving the `site/` folder in `FrankieBiz/hardset`.
GitHub Pages cannot select a subdirectory from a branch source (only `/` or `/docs`), and
the site stays in `site/`, so `.github/workflows/pages.yml` uploads that folder as the
Pages artifact and deploys it.

The public URLs are:

- <https://frankiebiz.github.io/hardset/>
- <https://frankiebiz.github.io/hardset/privacy.html>
- <https://frankiebiz.github.io/hardset/support.html>

The Pages source must be set to **GitHub Actions** once. After that, merging to `main`
deploys; no branch or folder selection is involved. The pages themselves contain no
placeholder copy.

1. In GitHub, open **Settings → Pages → Build and deployment**.
2. Set **Source** to **GitHub Actions**. Do not choose a branch or a folder.
3. Merge the change to `main`, or run **Actions → Deploy site to GitHub Pages → Run
   workflow**. The workflow checks out the repository, uploads `site/`, and deploys it.
4. Wait for the workflow and the `github-pages` environment deployment to finish, then
   open all three URLs above. Confirm `privacy.html` and `support.html` resolve at those
   exact paths (not 404) and every relative link works.
5. A custom domain can be added later in the Pages settings without changing the pages or
   their relative links. If one is added, update the three URLs in App Store Connect and in
   `docs/release/APP-STORE-METADATA.md` at that time.
6. Re-check the published pages after any edit. Every push to `main` redeploys the current
   `site/` folder.

The workflow is the only publisher. Do not configure a branch/folder source: Pages accepts
only `/` or `/docs` for a branch source, not the `site/` folder, so that path returns 422.

## Before publishing

- Confirm the operator line: Frankie Bisignano, frankabisignano@gmail.com.
- Confirm the "last updated" date on the privacy page (currently 23 November
  2026).
- Confirm the price wording: free download; $19.99 launch and $29.99 standing
  for the optional Lifetime unlock (D17).
- Confirm the 1.0 build removes Apple Health (D25) before the privacy and support
  pages claim it does. The current branch still links HealthKit; see the
  verification note in `docs/release/APP-STORE-METADATA.md`.
