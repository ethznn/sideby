#!/usr/bin/env python3
"""Verify the deployable site, including project-path links and bilingual SEO."""
import argparse
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse, unquote
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
    expected.update(f'assets/{stem}-{language}.{ext}' for stem, exts in [('sideby-kinetic', ['png', 'gif']), ('sideby-save-workspace', ['png']), ('sideby-context-capture', ['png'])] for ext in exts)
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
    assert page.find('meta', property='og:image', content=base + f'assets/sideby-kinetic-{language}.png')
    assert page.find('meta', name='twitter:card', content='summary_large_image')
    assert not page.find('meta', name='robots', content='noindex')
    assert 'noindex' not in text.lower()
    assert '${' not in text and '/Users/' not in text and '127.0.0.1' not in text
    assert all(not urlparse(tag.get('src', '')).netloc for tag in page.find('script')), 'No third-party script dependency expected'
    data = json.loads(page.json_text); app = next(item for item in data['@graph'] if item['@type'] == 'SoftwareApplication')
    assert app['name'] == 'Sideby' and app['offers']['price'] == '0'
    assert 'aggregateRating' not in app and 'review' not in app, 'Only publish actual reviews'
    assert app['downloadUrl'] == 'https://github.com/ethznn/sideby/releases/latest'
    assert len(page.find('a', href=app['downloadUrl'])) >= 2
    assert len(page.find('details')) == 6
    assert page.find('button', id='play-film', **{'aria-pressed':'false'})
    for tag, attrs in page.tags:
        if tag == 'img':
            assert attrs.get('alt') and attrs.get('width') and attrs.get('height')
            assert not attrs['src'].endswith('.gif'), 'Start with a poster so JavaScript can respect reduced motion'
        for attribute in ['href', 'src', 'data-motion', 'data-poster']:
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
