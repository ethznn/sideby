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
checkout_url = 'https://checkout.dodopayments.com/buy/pdt_0NsE1BI1QjY6sK2EF51FN?quantity=1'
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
                  home_path=parsed.path + path, repo_url=repo, checkout_url=checkout_url,
                  docs_url='#how',
                  privacy_url=parsed.path + path + 'privacy/',
                  terms_url=parsed.path + path + 'terms/', refunds_url=parsed.path + path + 'refunds/',
                  support_url=parsed.path + path + 'support/',
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
    values['pricing_fact_items'] = ''.join(f'<div><dt>{esc(title)}</dt><dd>{esc(text)}</dd></div>' for title, text in content['pricing_facts'])
    values['benefit_items'] = ''.join(f'<li>{esc(text)}</li>' for text in content['benefits'])
    values['step_items'] = ''.join(f'<li><div><h3>{esc(title)}</h3><p>{esc(text)}</p></div></li>' for title, text in content['steps'])
    values['feature_items'] = ''.join(f'<section><h3>{esc(title)}</h3><p>{esc(text)}</p></section>' for title, text in content['small_features'])
    faq_items = []
    for index, (title, text) in enumerate(content['faqs']):
        attributes = ' id="privacy"' if index == len(content['faqs']) - 1 else ''
        faq_items.append(f'<details{attributes}><summary>{esc(title)}</summary><p>{esc(text)}</p></details>')
    values['faq_items'] = ''.join(faq_items)
    values['purchase_faq_items'] = ''.join(
        f'<details><summary>{esc(title)}</summary><p>{esc(text)}</p></details>'
        for title, text in content['purchase_faqs'])
    graph = {'@context': 'https://schema.org', '@graph': [
        {'@type': 'WebSite', '@id': base + '#website', 'name': 'Sideby', 'url': base, 'inLanguage': ['en', 'ko']},
        {'@type': 'WebPage', '@id': canonical, 'url': canonical, 'name': content['title'],
         'description': content['description'], 'inLanguage': language, 'isPartOf': {'@id': base + '#website'},
         'about': {'@id': base + '#app'}},
        {'@type': 'SoftwareApplication', '@id': base + '#app', 'name': 'Sideby',
         'url': base, 'description': content['description'], 'operatingSystem': 'macOS 14 or later',
         'applicationCategory': 'UtilitiesApplication', 'processorRequirements': 'Apple silicon',
         'downloadUrl': 'https://github.com/ethznn/sideby/releases/latest/download/Sideby.dmg',
         'inLanguage': ['en', 'ko', 'ja', 'zh-Hant', 'es-419', 'pt-BR'],
         'offers': {'@type': 'Offer', 'price': '12.99', 'priceCurrency': 'USD', 'url': checkout_url}}
    ]}
    values['structured_data'] = json.dumps(graph, ensure_ascii=False).replace('<', '\\u003c')
    target = output / path
    target.mkdir(parents=True, exist_ok=True)
    (target / 'index.html').write_text(template.substitute(values))
policy_template = Template((ROOT / 'site/policy.html').read_text())
site_paths = ['', 'ko/']
for language in ['en', 'ko']:
    content = json.loads((ROOT / f'site/content/{language}.json').read_text())
    policies = json.loads((ROOT / f'site/policies/{language}.json').read_text())
    prefix = '' if language == 'en' else 'ko/'
    for slug, policy in policies['pages'].items():
        path = prefix + slug + '/'
        site_paths.append(path)
        links = ''.join(f'<a href="{parsed.path}{prefix}{key}/"' + (' aria-current="page"' if key == slug else '') + f'>{esc(value["title"])}</a>' for key, value in policies['pages'].items())
        sections = []
        for section in policy['sections']:
            body = ''.join(f'<p>{esc(paragraph)}</p>' for paragraph in section['paragraphs'])
            body += ''.join(f'<p><a href="{esc(parsed.path + href[len('/sideby/'):] if href.startswith('/sideby/') else href, quote=True)}">{esc(label)} ↗</a></p>' for label, href in section.get('links', []))
            section_id = f' id="{esc(section["id"], quote=True)}"' if 'id' in section else ''
            sections.append(f'<section{section_id}><h2>{esc(section["title"])}</h2>{body}</section>')
        values = dict(lang=language, title=esc(policy['title']), description=esc(policy['summary'], quote=True),
                      canonical=base + path, en_url=base + slug + '/', ko_url=base + 'ko/' + slug + '/',
                      en_current='aria-current="page"' if language == 'en' else '',
                      ko_current='aria-current="page"' if language == 'ko' else '',
                      base_path=parsed.path, home_path=parsed.path + prefix, style_version=style_version,
                      skip=esc(content['skip']), language_label=esc(content['language_label']),
                      nav_pricing=esc(content['nav_pricing']), legal_nav=esc(content['legal_nav']),
                      policy_links=links, summary=esc(policy['summary']), sections=''.join(sections),
                      notice=esc(policies['notice']), updated=esc(policies['updated']),
                      publisher=esc(content['publisher']), contact_label=esc(content['contact_label']))
        target = output / path
        target.mkdir(parents=True, exist_ok=True)
        (target / 'index.html').write_text(policy_template.substitute(values))
for filename in ['style.css', 'site.js']:
    shutil.copyfile(ROOT / 'site' / filename, assets / filename)
(output / '.nojekyll').write_text('')
(output / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{esc(base + path)}</loc></url>\n' for path in site_paths) + '</urlset>\n')
(output / '404.html').write_text(f'<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Page not found — Sideby</title><h1>Page not found</h1><p><a href="{esc(parsed.path)}">Back to Sideby / Sideby로 돌아가기</a></p></html>')
print(f'Built English and Korean site: {output}')
