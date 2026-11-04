// The toolkit's shared preference; only the theme is persisted, never study data.
(() => {
  const key = 'bp-theme';
  const system = matchMedia('(prefers-color-scheme: light)');
  let saved;
  try { saved = localStorage.getItem(key); } catch (_) {}
  let theme = ['light', 'dark'].includes(saved) ? saved : system.matches ? 'light' : 'dark';
  function apply(value, persist = false) {
    theme = value;
    document.documentElement.dataset.theme = theme;
    document.querySelectorAll('.theme-toggle').forEach(button => {
      button.textContent = theme === 'dark' ? 'Light mode' : 'Dark mode';
      button.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`);
    });
    if (persist) {
      saved = theme;
      try { localStorage.setItem(key, theme); } catch (_) {}
    }
    window.dispatchEvent(new CustomEvent('ecrf-theme', { detail: theme }));
  }
  apply(theme);
  document.addEventListener('DOMContentLoaded', () => apply(theme));
  document.addEventListener('click', e => {
    if (e.target.closest('.theme-toggle')) apply(theme === 'dark' ? 'light' : 'dark', true);
  });
  system.addEventListener('change', () => { if (!['light', 'dark'].includes(saved)) apply(system.matches ? 'light' : 'dark'); });
  window.addEventListener('storage', e => {
    if (e.key === key) { saved = e.newValue; apply(['light', 'dark'].includes(saved) ? saved : system.matches ? 'light' : 'dark'); }
  });
})();
