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

## Publish (GitHub Pages, this repository)

Hosting is decided: **GitHub Pages**, free, serving the `site/` folder from `main` in
`FrankieBiz/hardset`. The public URLs are:

- <https://frankiebiz.github.io/hardset/>
- <https://frankiebiz.github.io/hardset/privacy.html>
- <https://frankiebiz.github.io/hardset/support.html>

The only remaining step is the owner pressing Publish. Until Pages is enabled, those URLs
return 404; the files and their relative links need no change.

1. In GitHub, open **Settings → Pages → Build and deployment**.
2. Set **Source** to **Deploy from a branch**.
3. Set **Branch** to `main` and **Folder** to `/site`. Save.
4. Or do the same from the CLI:

   ```bash
   gh api repos/FrankieBiz/hardset/pages -X POST \
     -f "source[branch]=main" -f "source[path]=/site"
   ```

5. Wait for the Pages deployment to finish, then open all three URLs above. Confirm
   `privacy.html` and `support.html` resolve at those exact paths (not 404) and every
   relative link works.
6. A custom domain can be added later in the Pages settings without changing the pages or
   their relative links. If one is added, update the three URLs in App Store Connect and
   in `docs/release/APP-STORE-METADATA.md` at that time.
7. Re-check the published pages after any edit. GitHub Pages serves the new commit after
   its deployment finishes.

The pages themselves contain no placeholder copy. The three App Store Connect values are
already filled in `docs/release/APP-STORE-METADATA.md`; pressing Publish is the only
hosting blocker left.

## Before publishing

- Confirm the operator line: Frankie Bisignano, frankabisignano@gmail.com.
- Confirm the "last updated" date on the privacy page (currently 23 November
  2026).
- Confirm the price wording: free download; $19.99 launch and $29.99 standing
  for the optional Lifetime unlock (D17).
- Confirm the 1.0 build removes Apple Health (D25) before the privacy and support
  pages claim it does. The current branch still links HealthKit; see the
  verification note in `docs/release/APP-STORE-METADATA.md`.
