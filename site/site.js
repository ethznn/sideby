'use strict';
function setupFilm(buttonID, imageID, autoplay) {
  const button = document.getElementById(buttonID);
  const film = document.getElementById(imageID);
  if (button && film) {
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)');
    let requestedPlayback = autoplay && !motion.matches;
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
      requestedPlayback = autoplay && !event.matches;
      updatePlayback();
    });
    document.addEventListener('visibilitychange', updatePlayback);
    updatePlayback();
  }
}
setupFilm('play-film', 'film', true);
setupFilm('play-tutorial', 'tutorial-film', false);
