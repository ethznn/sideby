'use strict';
const button = document.getElementById('play-film');
const film = document.getElementById('film');
if (button && film) {
  const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let requestedPlayback = !motion.matches;
  function updatePlayback() {
    const playing = requestedPlayback && !document.hidden;
    const source = playing ? button.dataset.motion : button.dataset.poster;
    if (film.getAttribute('src') !== source) film.src = source;
    button.setAttribute('aria-pressed', String(playing));
    button.textContent = playing ? button.dataset.pause : button.dataset.play;
  }
  button.hidden = false;
  button.addEventListener('click', () => {
    requestedPlayback = !requestedPlayback;
    updatePlayback();
  });
  motion.addEventListener('change', event => {
    requestedPlayback = !event.matches;
    updatePlayback();
  });
  document.addEventListener('visibilitychange', updatePlayback);
  updatePlayback();
}
