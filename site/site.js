'use strict';
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
