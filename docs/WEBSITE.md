# Sideby website

The public product site is separate from the owner's portfolio:

- English: <https://ethznn.github.io/sideby/>
- Korean: <https://ethznn.github.io/sideby/ko/>
- Sitemap: <https://ethznn.github.io/sideby/sitemap.xml>

This repository deploys only the `/sideby/` project site. The portfolio at
`https://ethznn.github.io/` belongs to the separate `ethznn.github.io` repository.
Do not change that repository or its Pages settings when publishing Sideby.

## Edit and preview

Text lives in `site/content/en.json` and `site/content/ko.json`. Both languages
share `site/template.html`, `site/style.css`, and `site/site.js`.

```sh
python3 scripts/build_site.py
python3 scripts/check_site.py
node --check site/site.js
bash scripts/check_public_docs.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory .build/website
```

Open `http://127.0.0.1:8765/sideby/` or `/sideby/ko/`. The local preview keeps the
production canonical URLs. Review both languages at narrow and wide widths,
light and dark appearance, keyboard navigation, and with reduced motion.

The hero film may play automatically while visible, except when reduced motion is
preferred. All three short films start only on request. Native controls support
pause, seeking and fullscreen. Videos pause outside the viewport or in a hidden
tab; manually paused videos stay paused. Download links work without JavaScript.
No analytics, external fonts, or third-party JavaScript are included.

Scripts, styles, screenshots, posters and videos use content-hashed URLs. The
current media show the 1.3 gallery, name editor and large connection table. An
explicit disclosure reveals the screenshot with the Space list expanded.

## Deployment

`.github/workflows/pages.yml` builds and checks the site on relevant pull requests.
After a relevant change reaches `main`, it uploads the generated static files and
deploys them with GitHub Actions to this repository's GitHub Pages site. The
workflow also supports manual dispatch. Set this repository's Pages build source
to **GitHub Actions**; no branch containing generated HTML is needed.

The builder copies an explicit list of reviewed public screenshots and posters from
`docs/images/` and final MP4 exports from `docs/videos/`. It never uploads the
repository root, app bundles, local captures or production directories. `check_site.py` checks the exact deployment file
list, metadata, language links, structured data, anchors, and resource paths.
New or replaced media still needs visual privacy review before publication.

Public app downloads are temporarily paused. The site and READMEs announce this
status without linking to releases or installers. This repository contains only
the public website and reviewed marketing media; do not publish app source, app
bundles, DMGs, or historical application commits here. Website changes do not
bump the app version or update Sparkle.

## Search setup

The pages contain searchable HTML, unique titles and descriptions, self-canonical
URLs, reciprocal English/Korean `hreflang` links, Open Graph/Twitter preview
metadata, and `WebSite`, `WebPage`, and `SoftwareApplication` structured data.
Application claims describe the current product: it connects existing macOS
Spaces and restores saved positions and sizes for eligible windows on ordinary
desktops. It does not reopen apps/documents or restore their contents. Saved setup
images persist locally; ordinary preview images use a bounded memory cache.

The application data includes the supported platform. It omits download URLs,
prices, offers, and app-license claims while distribution is being prepared. It
does not fabricate ratings or reviews. This markup alone does not establish
eligibility for Google's software-app rich results, which have additional
requirements: <https://developers.google.com/search/docs/appearance/structured-data/software-app>.

After the site is live:

The owner's Google Search Console verification tag is included in
`site/template.html`. Keep it in place after verification so ownership can be
rechecked. It is a public verification token, not an API credential.

1. In Google Search Console, add the **URL-prefix** property
   `https://ethznn.github.io/sideby/` using the owner's Google account.
2. Verify ownership with Google's HTML tag in `site/template.html`, then redeploy.
   Do not replace the portfolio's verification or use a DNS Domain property for
   the shared `github.io` domain.
3. Submit `https://ethznn.github.io/sideby/sitemap.xml` in that property.
4. Inspect the English and Korean URLs, run a live test, and request indexing.
5. Check Page indexing and Search results for impressions, clicks, and queries.
   Search clicks and release-download counts are different from installed users.

Search Console: <https://search.google.com/search-console/about>.
Publishing a page or submitting a sitemap does not guarantee indexing or ranking.
See <https://developers.google.com/search/docs/crawling-indexing/ask-google-to-recrawl>.

`robots.txt` only applies at the host root, `https://ethznn.github.io/robots.txt`.
A file at `/sideby/robots.txt` would not control crawling, so this project does not
generate one. The root site's current `Allow: /` permits this project too. Submit
the project sitemap directly; there is no need to modify the portfolio sitemap.

If a custom domain is introduced later, change the builder's `--base-url`, update
the matching checker argument, repository homepage and README links, and verify
the new site property and redirects before switching. Keep one canonical URL
per language.
