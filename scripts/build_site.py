#!/usr/bin/env python3
"""Build the Sideby project site from explicit public inputs; no packages required."""
import argparse
import hashlib
import html
import json
import shutil
from pathlib import Path
from string import Template
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / '.build/website/sideby')
parser.add_argument('--base-url', default='https://ethznn.github.io/sideby/')
args = parser.parse_args()
base = args.base_url.rstrip('/') + '/'
parsed = urlparse(base)
if parsed.scheme != 'https' or not parsed.netloc or parsed.query or parsed.fragment:
    parser.error('--base-url must be an HTTPS site URL without a query or fragment')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
assets = output / 'assets'
assets.mkdir(exist_ok=True)
template = Template((ROOT / 'site/template.html').read_text())
esc = html.escape
repo = 'https://github.com/ethznn/sideby'
script_version = hashlib.sha256((ROOT / 'site/site.js').read_bytes()).hexdigest()[:12]
style_version = hashlib.sha256((ROOT / 'site/style.css').read_bytes()).hexdigest()[:12]
screenshots = ['gallery', 'editor', 'spaces', 'rename']
films = ['marketing', 'screens-together', 'saved-layouts', 'find-return']

def media(name, extension):
    source = ROOT / 'docs' / ('videos' if extension == 'mp4' else 'images') / f'sideby-{name}.{extension}'
    version = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
    shutil.copyfile(source, assets / source.name)
    return version

for language in ['en', 'ko']:
    content = json.loads((ROOT / f'site/content/{language}.json').read_text())
    path = '' if language == 'en' else 'ko/'
    canonical = base + path
    values = {k: esc(v, quote=True) for k, v in content.items() if isinstance(v, str)}
    values.update(base_url=base, base_path=parsed.path, canonical=canonical, script_version=script_version, style_version=style_version,
                  home_path=parsed.path + path, repo_url=repo,
                  docs_url='#how',
                  privacy_url='#privacy',
                  og_locale='en_US' if language == 'en' else 'ko_KR',
                  og_alternate='ko_KR' if language == 'en' else 'en_US',
                  en_current='aria-current="page"' if language == 'en' else '',
                  ko_current='aria-current="page"' if language == 'ko' else '')
    for stem in screenshots:
        values[f'{stem}_image_version'] = media(f'{stem}-{language}', 'png')
    for stem in films:
        for extension in ['png', 'mp4']:
            values[f'{stem}_{extension}_version'] = media(f'{stem}-{language}', extension)
    assert [item[0] for item in content['short_films']] == films[1:]
    values['short_film_items'] = ''.join(
        f'<article class="short-film"><div><h3>{esc(title)}</h3><p class="body-copy">{esc(description)}</p></div>'
        f'<figure class="film"><video id="{stem}" controls muted loop playsinline preload="none" width="1920" height="1080" '
        f'aria-label="{esc(title, quote=True)}" poster="{parsed.path}assets/sideby-{stem}-{language}.png?v={values[stem + "_png_version"]}" '
        f'src="{parsed.path}assets/sideby-{stem}-{language}.mp4?v={values[stem + "_mp4_version"]}"></video>'
        f'<figcaption><a href="{parsed.path}assets/sideby-{stem}-{language}.mp4?v={values[stem + "_mp4_version"]}" download>{esc(content["video_download"])} ↓</a></figcaption></figure></article>'
        for stem, title, description in content['short_films'])
    values['benefit_items'] = ''.join(f'<li>{esc(text)}</li>' for text in content['benefits'])
    values['step_items'] = ''.join(f'<li><div><h3>{esc(title)}</h3><p>{esc(text)}</p></div></li>' for title, text in content['steps'])
    values['feature_items'] = ''.join(f'<section><h3>{esc(title)}</h3><p>{esc(text)}</p></section>' for title, text in content['small_features'])
    faq_items = []
    for index, (title, text) in enumerate(content['faqs']):
        attributes = ' id="privacy"' if index == len(content['faqs']) - 1 else ''
        faq_items.append(f'<details{attributes}><summary>{esc(title)}</summary><p>{esc(text)}</p></details>')
    values['faq_items'] = ''.join(faq_items)
    graph = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'WebSite', '@id': base + '#website', 'name': 'Sideby', 'url': base, 'inLanguage': ['en', 'ko']},
        {'@type': 'WebPage', '@id': canonical, 'url': canonical, 'name': content['title'],
         'description': content['description'], 'inLanguage': language, 'isPartOf': {'@id': base + '#website'},
         'about': {'@id': base + '#app'}},
        {'@type': 'SoftwareApplication', '@id': base + '#app', 'name': 'Sideby',
         'url': base, 'description': content['description'], 'operatingSystem': 'macOS 14 or later',
         'applicationCategory': 'UtilitiesApplication', 'processorRequirements': 'Apple silicon'}
    ]}
    values['structured_data'] = json.dumps(graph, ensure_ascii=False).replace('<', '\\u003c')
    target = output / path
    target.mkdir(parents=True, exist_ok=True)
    (target / 'index.html').write_text(template.substitute(values))
for filename in ['style.css', 'site.js']:
    shutil.copyfile(ROOT / 'site' / filename, assets / filename)
(output / '.nojekyll').write_text('')
(output / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{esc(base + path)}</loc></url>\n' for path in ['', 'ko/']) + '</urlset>\n')
(output / '404.html').write_text(f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Page not found — Sideby</title><h1>Page not found</h1><p><a href="{esc(parsed.path)}">Back to Sideby / Sideby로 돌아가기</a></p></html>')
print(f'Built English and Korean site: {output}')
