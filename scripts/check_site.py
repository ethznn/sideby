#!/usr/bin/env python3
"""Verify the deployable site, including project-path links and bilingual SEO."""
import argparse
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote, parse_qs
import xml.etree.ElementTree as ET

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.tags = []; self.text = []; self.json_text = ''; self.in_json = False
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        data = dict(attrs); self.tags.append((tag, data))
        if tag == 'script' and data.get('type') == 'application/ld+json': self.in_json = True
    def handle_endtag(self, tag):
        if tag == 'script': self.in_json = False
    def handle_data(self, text):
        if self.in_json: self.json_text += text
        else: self.text.append(text)
    def find(self, tag, **attrs):
        return [data for name, data in self.tags if name == tag and all(data.get(k) == v for k, v in attrs.items())]

parser = argparse.ArgumentParser()
parser.add_argument('directory', nargs='?', type=Path, default=Path('.build/website/sideby'))
parser.add_argument('--base-url', default='https://ethznn.github.io/sideby/')
args = parser.parse_args(); root = args.directory.resolve()
base = args.base_url.rstrip('/') + '/'; parsed_base = urlparse(base)
expected = {'index.html', 'ko/index.html', '404.html', '.nojekyll', 'sitemap.xml', 'assets/style.css', 'assets/site.js'}
for language in ['en', 'ko']:
    expected.update(f'assets/sideby-{stem}-{language}.png' for stem in ['gallery', 'editor', 'spaces', 'rename'])
    expected.update(f'assets/sideby-{stem}-{language}.{ext}' for stem in ['marketing', 'screens-together', 'saved-layouts', 'find-return'] for ext in ['png', 'mp4'])
actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file()}
assert actual == expected, f'Unexpected deployment files: {actual ^ expected}'
assert not any(p.is_symlink() for p in root.rglob('*')), 'Symlinks are not deployable'
titles = []; descriptions = []
for language, relative in [('en', 'index.html'), ('ko', 'ko/index.html')]:
    text = (root / relative).read_text(); page = Page(text)
    canonical = base + ('' if language == 'en' else 'ko/')
    assert page.find('html', lang=language)
    assert len(page.find('h1')) == 1
    assert page.find('link', rel='canonical', href=canonical)
    for code, url in [('en', base), ('ko', base + 'ko/'), ('x-default', base)]:
        assert page.find('link', rel='alternate', hreflang=code, href=url)
    description = page.find('meta', name='description')[0]['content']
    assert len(description) > 50; descriptions.append(description)
    assert page.find('meta', property='og:url', content=canonical)
    film_hash = hashlib.sha256((root / f'assets/sideby-marketing-{language}.png').read_bytes()).hexdigest()[:12]
    assert page.find('meta', property='og:image', content=base + f'assets/sideby-marketing-{language}.png?v={film_hash}')
    assert page.find('meta', name='twitter:card', content='summary_large_image')
    assert not page.find('meta', name='robots', content='noindex')
    assert 'noindex' not in text.lower()
    assert '${' not in text and '/Users/' not in text and '127.0.0.1' not in text
    assert all(not urlparse(tag.get('src', '')).netloc for tag in page.find('script')), 'No third-party script dependency expected'
    script_version = hashlib.sha256((root / 'assets/site.js').read_bytes()).hexdigest()[:12]
    assert page.find('script', src=f'{parsed_base.path}assets/site.js?v={script_version}'), 'Version the script URL so returning visitors receive playback updates'
    data = json.loads(page.json_text); app = next(item for item in data['@graph'] if item['@type'] == 'SoftwareApplication')
    assert app['name'] == 'Sideby'
    assert not {'downloadUrl', 'offers', 'isAccessibleForFree', 'license'} & app.keys(), 'Do not advertise unavailable downloads or unannounced pricing'
    assert page.find('details', id='privacy')
    assert page.find('p', **{'class': 'availability'})
    for link in page.find('a'):
        href = link.get('href', '')
        assert '/releases' not in href and not urlparse(href).path.lower().endswith(('.dmg', '.pkg', '.zip')), 'App downloads are paused'
    assert all(claim not in text.lower() for claim in ['free &amp; open source', 'free, open-source', '무료 오픈소스', 'mit license'])
    assert 'aggregateRating' not in app and 'review' not in app, 'Only publish actual reviews'
    assert len(page.find('a', href='#how')) >= 3
    assert len(page.find('details')) == 8
    assert page.find('details', **{'class': 'editor-overview'}), 'Offer the full editor as an optional view'
    assert page.find('section', id='edit')
    assert page.find('details', id='table-preview'), 'Offer the large Table screenshot with an explicit disclosure'
    assert page.find('a', href='#edit')
    assert len(page.find('video')) == 4, 'Publish the main film and all three short films'
    for video_id, stem in [('film', 'marketing'), ('screens-together', 'screens-together'), ('saved-layouts', 'saved-layouts'), ('find-return', 'find-return')]:
        version = hashlib.sha256((root / f'assets/sideby-{stem}-{language}.mp4').read_bytes()).hexdigest()[:12]
        video = page.find('video', id=video_id, src=f'{parsed_base.path}assets/sideby-{stem}-{language}.mp4?v={version}')[0]
        assert all(attribute in video for attribute in ['controls', 'muted', 'playsinline', 'loop'])
        assert video['preload'] == 'none' and 'autoplay' not in video, 'Respect reduced motion before loading or playing video'
        assert video.get('aria-label') and video.get('poster') and video['width'] == '1920' and video['height'] == '1080'
        assert video.get('data-autoplay') == ('true' if video_id == 'film' else None)
    for stem in ['gallery', 'editor', 'spaces', 'rename']:
        version = hashlib.sha256((root / f'assets/sideby-{stem}-{language}.png').read_bytes()).hexdigest()[:12]
        assert page.find('img', src=f'{parsed_base.path}assets/sideby-{stem}-{language}.png?v={version}', width='2880', height='1800')
    assert 'https://buymeacoffee.com/ethznn' in text and 'class="button coffee"' in text
    assert '1.3.0' in text and '1.2.0' not in text
    style_version = hashlib.sha256((root / 'assets/style.css').read_bytes()).hexdigest()[:12]
    assert page.find('link', rel='stylesheet', href=f'{parsed_base.path}assets/style.css?v={style_version}')
    for tag, attrs in page.tags:
        if tag == 'img':
            assert attrs.get('alt') and attrs.get('width') and attrs.get('height')
            assert not attrs['src'].endswith('.gif'), 'Start with a poster so JavaScript can respect reduced motion'
        for attribute in ['href', 'src', 'poster']:
            path = attrs.get(attribute)
            if not path: continue
            parsed = urlparse(path)
            if parsed.scheme:
                assert parsed.scheme == 'https'
                if parsed.netloc != parsed_base.netloc: continue
            elif path.startswith('#'):
                assert any(a.get('id') == parsed.fragment for _, a in page.tags), f'Broken anchor: {path}'
                continue
            assert parsed.path.startswith(parsed_base.path), f'Link escapes project site: {path}'
            local = unquote(parsed.path[len(parsed_base.path):])
            target = root / local
            if parsed.path.endswith('/'): target = target / 'index.html'
            assert target.is_file(), f'Broken resource: {path}'
            if target.suffix in ['.png', '.gif', '.mp4']:
                version = hashlib.sha256(target.read_bytes()).hexdigest()[:12]
                assert parse_qs(parsed.query).get('v') == [version], f'Stale media URL: {path}'
            if parsed.fragment and target.suffix == '.html':
                target_page = Page(target.read_text())
                assert any(a.get('id') == parsed.fragment for _, a in target_page.tags), f'Broken anchor: {path}'
    title = text.split('<title>')[1].split('</title>')[0]; titles.append(title)
    assert 'Mac' in title and 'Sideby' in title
    print(f'PASS {language}: canonical, language links, social metadata, JSON-LD, content, assets, project paths')
assert len(set(titles)) == 2 and len(set(descriptions)) == 2
urls = [node.text for node in ET.parse(root / 'sitemap.xml').findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
assert urls == [base, base + 'ko/']
assert Page((root / '404.html').read_text()).find('meta', name='robots', content='noindex')
print(f'PASS sitemap and deployment allowlist: {len(actual)} public files; no app bundles or local production files')
