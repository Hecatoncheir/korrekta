const icon = (name, className = '') => `<svg class="icon ${className}" aria-hidden="true"><use href="assets/icons.svg#${name}"></use></svg>`;
const mark = `<svg viewBox="0 0 100 100" class="brand-mark" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="15" stroke-linecap="round" stroke-linejoin="round"><path d="M30 20C25 35 24 58 28 78"/><path d="M73 22C63 39 49 47 28 51"/><path d="M46 46C54 55 61 70 76 75"/></g></svg>`;
const storage = {
  get(key, fallback) { try { return JSON.parse(localStorage.getItem(`korrekta-${key}`)) ?? fallback; } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem(`korrekta-${key}`, JSON.stringify(value)); } catch {} }
};
document.documentElement.dataset.theme = storage.get('theme', 'light');
document.querySelectorAll('[data-mark]').forEach(el => el.innerHTML = mark);
document.querySelectorAll('[data-icon]').forEach(el => el.innerHTML = icon(el.dataset.icon));
function renderTheme() {
  document.querySelectorAll('[data-theme-toggle]').forEach(button => {
    const dark = document.documentElement.dataset.theme === 'dark';
    button.innerHTML = icon(dark ? 'sun' : 'moon');
    button.setAttribute('aria-label', dark ? 'Светлая тема' : 'Тёмная тема');
    button.title = dark ? 'Светлая тема' : 'Тёмная тема';
  });
}
document.querySelectorAll('[data-theme-toggle]').forEach(button => button.addEventListener('click', () => {
  document.documentElement.classList.add('theme-changing');
  const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = theme;
  storage.set('theme', theme);
  renderTheme();
  setTimeout(() => document.documentElement.classList.remove('theme-changing'), 450);
}));
renderTheme();
let toastTimer;
function toast(message) {
  const node = document.getElementById('toast');
  if (!node) return;
  node.textContent = message;
  node.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.remove('show'), 3200);
}
function openDialog(id) { document.getElementById(id).showModal(); }
document.querySelectorAll('[data-open]').forEach(el => el.addEventListener('click', () => openDialog(el.dataset.open)));
document.querySelectorAll('[data-close]').forEach(el => el.addEventListener('click', () => el.closest('dialog').close()));
document.querySelectorAll('dialog').forEach(dialog => dialog.addEventListener('click', event => {
  if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
  }
}));
