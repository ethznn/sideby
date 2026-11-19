'use strict';

function selectHomepageLanguage() {
  const links = [...document.querySelectorAll('.languages a[lang]')];
  const english = links.find(link => link.lang === 'en');
  const korean = links.find(link => link.lang === 'ko');
  if (!english || !korean) return;

  const key = 'sideby.homepage.language';
  function remember(language) {
    try { localStorage.setItem(key, language); } catch { /* Storage is optional. */ }
  }
  for (const link of links) link.addEventListener('click', () => remember(link.lang));

  const current = new URL(location.href);
  if (document.documentElement.lang !== 'en') return; // Respect shared Korean links.
  if (current.searchParams.get('lang') === 'en') {
    remember('en');
    return;
  }
  let preference;
  try { preference = localStorage.getItem(key); } catch { /* Use browser preferences. */ }
  if (!['ko', 'en'].includes(preference)) {
    preference = (navigator.languages || [navigator.language])
      .map(language => language.toLowerCase().split('-')[0])
      .find(language => language === 'ko' || language === 'en');
  }
  if (preference === 'ko') {
    const target = new URL(korean.href);
    target.search = current.search;
    target.hash = current.hash;
    location.replace(target.href);
  }
}
selectHomepageLanguage();

// Only the hero may start automatically. Every film stops outside the viewport
// or in a background tab; short examples start only when the visitor presses play.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
for (const film of document.querySelectorAll('video')) {
  let inView = false;
  let automatic = film.dataset.autoplay === 'true' && !reducedMotion.matches;
  let resumePlayback = false;
  function updatePlayback() {
    if (document.hidden || !inView) {
      if (!film.paused) {
        resumePlayback = true;
        film.pause();
      }
      return;
    }
    if (automatic || resumePlayback) {
      automatic = false;
      resumePlayback = false;
      film.play().catch(() => { /* Native controls remain available. */ });
    }
  }
  film.addEventListener('play', () => {
    automatic = false;
    if (document.hidden || !inView) updatePlayback();
  });
  film.addEventListener('pause', () => {
    if (!document.hidden && inView) resumePlayback = false;
  });
  new IntersectionObserver(entries => {
    inView = entries[0].isIntersecting;
    updatePlayback();
  }, { threshold: 0.15 }).observe(film);
  document.addEventListener('visibilitychange', updatePlayback);
  reducedMotion.addEventListener('change', event => {
    if (event.matches) {
      automatic = false;
      resumePlayback = false;
      film.pause();
    }
  });
}
