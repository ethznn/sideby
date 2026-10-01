'use strict';
const button = document.getElementById('play-film');
const film = document.getElementById('film');
if (button && film) {
  let playing = false;
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  function setPlayback(value) {
    playing = value;
    film.src = value ? button.dataset.motion : button.dataset.poster;
    button.setAttribute('aria-pressed', String(value));
    button.textContent = value ? button.dataset.pause : button.dataset.play;
  }
  button.hidden = false;
  button.addEventListener('click', () => setPlayback(!playing));
  motion.addEventListener('change', event => { if (event.matches) setPlayback(false); });
  document.addEventListener('visibilitychange', () => { if (document.hidden && playing) setPlayback(false); });
}
