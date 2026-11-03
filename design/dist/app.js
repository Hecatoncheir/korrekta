const EXAMPLE = 'Мне нравиться находить точные слова. Кажется это делает любую историю немного ближе.\n\nНа данный момент я пишу небольшой рассказ о городе, в котором всё по настоящему возможно.\n\nХочется сохранить свой голос — и просто убрать то, что мешает его услышать.';
const RULES = [
  { mode: 'proof', original: 'Мне нравиться', replacement: 'Мне нравится', highlight: 'нравиться', fixed: 'нравится', category: 'grammar', label: 'ГРАММАТИКА', explanation: 'Мне что делает? Нравится. В форме третьего лица мягкий знак не нужен.', dictionary: 'нравиться' },
  { mode: 'proof', original: 'Кажется это', replacement: 'Кажется, это', category: 'punctuation', label: 'ПУНКТУАЦИЯ', explanation: 'В этом предложении «кажется» — вводное слово. После него нужна запятая.' },
  { mode: 'proof', original: 'по настоящему', replacement: 'по-настоящему', category: 'grammar', label: 'ОРФОГРАФИЯ', explanation: 'Наречие с приставкой «по-» и окончанием «-ему» пишется через дефис.' },
  { mode: 'style', original: 'На данный момент', replacement: 'Сейчас', category: 'style', label: 'МОЖНО ПРОЩЕ', explanation: 'Более короткий вариант. Это предложение по стилю, а не ошибка.' },
  { mode: 'rewrite', original: 'Хочется сохранить свой голос — и просто убрать то, что мешает его услышать.', replacement: 'Хочется, чтобы за словами был слышен мой голос.', category: 'rewrite', label: 'ДРУГОЙ ВАРИАНТ', explanation: 'Один из способов выразить мысль короче. Выберите формулировку, которая вам ближе.' }
];
const editor = document.getElementById('editor');
const list = document.getElementById('suggestion-list');
let text = storage.get('draft', EXAMPLE);
if (typeof text !== 'string') text = EXAMPLE;
let mode = 'proof';
let filter = 'all';
let suggestions = [];
let selectedId = null;
let dictionary = storage.get('dictionary', []);
if (!Array.isArray(dictionary)) dictionary = [];
dictionary = dictionary.filter(word => typeof word === 'string');
let history = [];
let checked = false;
let busy = false;
let revision = 0;
let checkTimer;
let focusRange;
let pendingDocument = 'empty';

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}
function getText() { return editor.innerText.replace(/\r/g, ''); }
function save() {
  storage.set('draft', text);
  document.getElementById('save-state').textContent = 'Сохранён';
}
function updateCount() {
  const words = text.trim().match(/\S+/gu)?.length ?? 0;
  const characters = Array.from(text).length;
  const plural = (value, forms) => forms[value % 100 >= 11 && value % 100 <= 14 ? 2 : value % 10 === 1 ? 0 : value % 10 >= 2 && value % 10 <= 4 ? 1 : 2];
  document.getElementById('text-count').textContent = `${words} ${plural(words, ['слово', 'слова', 'слов'])} · ${characters} ${plural(characters, ['знак', 'знака', 'знаков'])}`;
  document.getElementById('undo').disabled = history.length === 0;
  document.getElementById('check-text').disabled = !text.trim() || busy;
}
function findSuggestions() {
  const results = [];
  for (const rule of RULES.filter(item => item.mode === mode)) {
    if (dictionary.some(word => word.toLocaleLowerCase('ru') === rule.dictionary?.toLocaleLowerCase('ru'))) continue;
    let from = 0;
    while (from < text.length) {
      const start = text.indexOf(rule.original, from);
      if (start < 0) break;
      const end = start + rule.original.length;
      const before = text[start - 1];
      const after = text[end];
      const boundary = char => !char || !/[\p{L}\p{N}_]/u.test(char);
      if (boundary(before) && boundary(after)) results.push({ ...rule, id: `${mode}-${start}`, start, end, revision });
      from = end;
    }
  }
  return results.sort((a, b) => a.start - b.start);
}
function renderEditor() {
  let html = '';
  let position = 0;
  for (const item of suggestions) {
    const markStart = item.start + (item.highlight ? item.original.indexOf(item.highlight) : 0);
    html += escapeHtml(text.slice(position, markStart));
    html += `<mark class="issue-mark ${item.category} ${selectedId === item.id ? 'selected' : ''}" data-issue="${item.id}">${escapeHtml(text.slice(markStart, item.end))}</mark>`;
    position = item.end;
  }
  editor.innerHTML = html + escapeHtml(text.slice(position));
  updateCount();
}
function renderEmpty() {
  const stateKey = `${mode}:${busy}:${checked}`;
  if (list.dataset.emptyState === stateKey) return;
  list.dataset.emptyState = stateKey;
  let heading = 'Здесь будут подсказки';
  let description = `Напишите текст и нажмите «${modeLabel()}».`;
  let emptyIcon = 'edit';
  if (busy) {
    heading = 'Смотрим внимательнее';
    description = 'Демонстрация проверки на примерах.';
    emptyIcon = 'text';
  } else if (checked) {
    heading = 'На этом всё';
    description = mode === 'proof' ? 'Встроенные примеры не нашли других совпадений. Полная проверка появится с подключением модели.' : 'Для этого текста нет других встроенных вариантов. Попробуйте пример текста.';
    emptyIcon = 'check';
  }
  list.innerHTML = `<div class="result-empty"><div class="empty-mark">${icon(emptyIcon)}</div><h3>${heading}</h3><p>${description}</p>${!busy && checked ? '<button class="text-button" data-example>Попробовать пример</button>' : ''}</div>`;
}
function renderSuggestions() {
  document.getElementById('issue-count').textContent = suggestions.length;
  document.getElementById('apply-all').disabled = suggestions.length === 0 || busy;
  document.getElementById('results-indicator').style.opacity = suggestions.length ? 1 : .3;
  const visible = suggestions.filter(item => filter === 'all' || item.category === filter);
  if (!suggestions.length) { renderEmpty(); return; }
  delete list.dataset.emptyState;
  if (!visible.length) {
    list.innerHTML = '<div class="result-empty"><h3>Здесь всё спокойно</h3><p>Подсказок этого типа нет. Остальные — во вкладке «Все».</p></div>';
    return;
  }
  list.innerHTML = visible.map(item => `<article class="suggestion ${item.category} ${selectedId === item.id ? 'selected' : ''}" data-card="${item.id}"><div class="suggestion-category"><span>${item.label}</span><button class="icon-button" data-ignore="${item.id}" aria-label="Отклонить: ${escapeHtml(item.highlight ?? item.original)}" title="Отклонить">${icon('close')}</button></div><div class="suggestion-change"><del>${escapeHtml(item.highlight ?? item.original)}</del>${icon('arrow')}<ins>${escapeHtml(item.fixed ?? item.replacement)}</ins></div><p>${item.explanation}</p><div class="suggestion-actions"><button class="accept" data-accept="${item.id}">${icon('check')}Принять</button>${item.dictionary ? `<button class="dictionary-add" data-word="${escapeHtml(item.dictionary)}">В словарь</button>` : ''}</div></article>`).join('');
}
function render() { renderEditor(); renderSuggestions(); }
function captureSelection() {
  const selection = window.getSelection();
  if (!selection?.rangeCount || !editor.contains(selection.anchorNode)) return null;
  const range = selection.getRangeAt(0);
  const prefix = document.createRange();
  prefix.selectNodeContents(editor);
  prefix.setEnd(range.startContainer, range.startOffset);
  return { start: prefix.toString().length, length: range.toString().length };
}
function restoreSelection(saved) {
  if (!saved) return;
  const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  let offset = 0;
  let startSet = false;
  let node;
  while ((node = walker.nextNode())) {
    const end = offset + node.textContent.length;
    if (!startSet && saved.start <= end) {
      range.setStart(node, Math.max(0, saved.start - offset));
      startSet = true;
    }
    if (startSet && saved.start + saved.length <= end) {
      range.setEnd(node, Math.max(0, saved.start + saved.length - offset));
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      return;
    }
    offset = end;
  }
}
function selectIssue(id) {
  selectedId = id;
  focusRange = captureSelection();
  render();
  restoreSelection(focusRange);
  document.querySelector(`[data-card="${id}"]`)?.scrollIntoView({ block: 'nearest' });
}
function checkText() {
  if (!text.trim() || busy) return;
  text = getText();
  busy = true;
  document.getElementById('check-text').classList.add('busy');
  checked = false;
  suggestions = [];
  selectedId = null;
  document.getElementById('check-label').textContent = 'Проверяем…';
  const version = revision;
  const selectedMode = mode;
  renderSuggestions();
  updateCount();
  clearTimeout(checkTimer);
  checkTimer = setTimeout(() => {
    busy = false;
    document.getElementById('check-text').classList.remove('busy');
    document.getElementById('check-label').textContent = modeLabel();
    if (version !== revision || selectedMode !== mode) { updateCount(); renderSuggestions(); return; }
    checked = true;
    suggestions = findSuggestions();
    selectedId = suggestions[0]?.id ?? null;
    focusRange = captureSelection();
    render();
    animateSuggestions();
    restoreSelection(focusRange);
    save();
  }, 480);
}
function snapshot() {
  history.push({ text, mode });
  if (history.length > 40) history.shift();
}
function apply(ids) {
  const chosen = suggestions.filter(item => ids.includes(item.id));
  if (!chosen.length) return;
  if (chosen.some(item => item.revision !== revision || text.slice(item.start, item.end) !== item.original) || getText() !== text) {
    invalidate();
    toast('Текст изменился. Запустите проверку ещё раз.');
    return;
  }
  const savedSelection = captureSelection();
  snapshot();
  for (const item of [...chosen].sort((a, b) => b.start - a.start)) {
    text = text.slice(0, item.start) + item.replacement + text.slice(item.end);
  }
  if (savedSelection) {
    for (const item of [...chosen].sort((a, b) => b.start - a.start)) {
      const delta = item.replacement.length - item.original.length;
      if (savedSelection.start >= item.end) savedSelection.start += delta;
      else if (savedSelection.start > item.start) savedSelection.start = item.start + item.replacement.length;
    }
    savedSelection.length = 0;
  }
  const old = suggestions;
  revision++;
  suggestions = old.filter(item => !ids.includes(item.id)).map(item => {
    const shift = chosen.filter(change => change.end <= item.start).reduce((sum, change) => sum + change.replacement.length - change.original.length, 0);
    return { ...item, start: item.start + shift, end: item.end + shift, id: `${mode}-${item.start + shift}`, revision };
  });
  selectedId = suggestions[0]?.id ?? null;
  render();
  const panel = document.querySelector('.editor-panel');
  panel.classList.remove('just-corrected');
  requestAnimationFrame(() => panel.classList.add('just-corrected'));
  restoreSelection(savedSelection);
  save();
  toast(chosen.length > 1 ? 'Исправления приняты. Замену можно отменить.' : 'Исправлено. Замену можно отменить.');
}
function invalidate() {
  text = getText();
  revision++;
  suggestions = [];
  selectedId = null;
  checked = false;
  busy = false;
  document.getElementById('check-text').classList.remove('busy');
  clearTimeout(checkTimer);
  document.getElementById('check-label').textContent = modeLabel();
}
function modeLabel() { return { proof: 'Проверить', style: 'Улучшить', rewrite: 'Предложить' }[mode]; }
function setMode(value) {
  mode = value;
  filter = 'all';
  busy = false;
  document.getElementById('check-text').classList.remove('busy');
  clearTimeout(checkTimer);
  suggestions = [];
  checked = false;
  selectedId = null;
  document.querySelectorAll('[data-mode]').forEach(button => button.setAttribute('aria-pressed', button.dataset.mode === mode));
  document.querySelectorAll('[data-filter]').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === filter));
  document.querySelector('.suggestion-filters').hidden = mode !== 'proof';
  document.getElementById('check-label').textContent = modeLabel();
  document.getElementById('suggestions-title').firstChild.textContent = mode === 'proof' ? 'Подсказки ' : 'Варианты ';
  render();
  syncModeIndicator();
}
function syncModeIndicator() {
  const active = document.querySelector('[data-mode][aria-pressed="true"]');
  const track = document.querySelector('.mode-switch');
  track.style.setProperty('--thumb-left', `${active.offsetLeft}px`);
  track.style.setProperty('--thumb-width', `${active.offsetWidth}px`);
}
let suggestionAnimation;
function animateSuggestions() {
  list.classList.remove('arriving');
  requestAnimationFrame(() => list.classList.add('arriving'));
  clearTimeout(suggestionAnimation);
  suggestionAnimation = setTimeout(() => list.classList.remove('arriving'), 800);
}
function loadExample() {
  snapshot();
  text = EXAMPLE;
  revision++;
  checked = true;
  suggestions = findSuggestions();
  selectedId = suggestions[0]?.id ?? null;
  render();
  save();
  toast('Загружен пример текста');
}
function addWord(value) {
  const word = value.trim();
  if (!word) return;
  if (dictionary.some(item => item.toLocaleLowerCase('ru') === word.toLocaleLowerCase('ru'))) { toast('Это слово уже в словаре'); return; }
  dictionary.push(word);
  storage.set('dictionary', dictionary);
  suggestions = suggestions.filter(item => item.dictionary?.toLocaleLowerCase('ru') !== word.toLocaleLowerCase('ru'));
  selectedId = suggestions[0]?.id ?? null;
  render();
  renderDictionary();
  toast('Слово добавлено в словарь');
}
function renderDictionary() {
  const target = document.getElementById('dictionary-list');
  target.innerHTML = dictionary.length ? dictionary.map((word, index) => `<span class="dictionary-chip">${escapeHtml(word)}<button data-remove-word="${index}" aria-label="Удалить слово ${escapeHtml(word)}">${icon('close')}</button></span>`).join('') : '<p class="dictionary-empty">Пока пусто. Здесь найдётся место вашим словам.</p>';
}
editor.addEventListener('input', () => {
  const selection = captureSelection();
  invalidate();
  render();
  restoreSelection(selection);
  history = [];
  updateCount();
  save();
});
editor.addEventListener('paste', event => {
  event.preventDefault();
  const value = event.clipboardData.getData('text/plain');
  const selection = window.getSelection();
  if (!selection.rangeCount) return;
  const range = selection.getRangeAt(0);
  range.deleteContents();
  const node = document.createTextNode(value);
  range.insertNode(node);
  range.setStartAfter(node);
  range.collapse(true);
  selection.removeAllRanges();
  selection.addRange(range);
  editor.dispatchEvent(new Event('input'));
});
editor.addEventListener('click', event => { const id = event.target.closest('[data-issue]')?.dataset.issue; if (id) selectIssue(id); });
list.addEventListener('click', event => {
  const accept = event.target.closest('[data-accept]');
  if (accept) { apply([accept.dataset.accept]); return; }
  const ignore = event.target.closest('[data-ignore]');
  if (ignore) { suggestions = suggestions.filter(item => item.id !== ignore.dataset.ignore); selectedId = suggestions[0]?.id ?? null; render(); return; }
  const word = event.target.closest('[data-word]');
  if (word) { addWord(word.dataset.word); return; }
  if (event.target.closest('[data-example]')) { loadExample(); return; }
  const card = event.target.closest('[data-card]');
  if (card) selectIssue(card.dataset.card);
});
document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => setMode(button.dataset.mode)));
document.querySelectorAll('[data-filter]').forEach(button => button.addEventListener('click', () => {
  filter = button.dataset.filter;
  document.querySelectorAll('[data-filter]').forEach(item => item.setAttribute('aria-pressed', item === button));
  renderSuggestions();
}));
document.getElementById('check-text').addEventListener('click', checkText);
document.getElementById('apply-all').addEventListener('click', () => apply(suggestions.map(item => item.id)));
document.getElementById('load-example').addEventListener('click', () => {
  pendingDocument = 'example';
  if (text && text !== EXAMPLE) {
    document.getElementById('new-title').textContent = 'Загрузить пример текста?';
    document.getElementById('confirm-new').textContent = 'Загрузить пример';
    openDialog('new-dialog');
  } else loadExample();
});
document.getElementById('undo').addEventListener('click', () => {
  const previous = history.pop();
  if (!previous) return;
  text = previous.text;
  revision++;
  setMode(previous.mode);
  checked = true;
  suggestions = findSuggestions();
  selectedId = suggestions[0]?.id ?? null;
  render(); save(); toast('Замена отменена');
});
document.getElementById('new-document').addEventListener('click', () => {
  pendingDocument = 'empty';
  document.getElementById('new-title').textContent = 'Начать новый текст?';
  document.getElementById('confirm-new').textContent = 'Новый текст';
  if (text) openDialog('new-dialog'); else editor.focus();
});
document.getElementById('confirm-new').addEventListener('click', () => {
  if (pendingDocument === 'example') { loadExample(); document.getElementById('new-dialog').close(); return; }
  snapshot(); text = ''; revision++; suggestions = []; checked = false; selectedId = null;
  render(); save(); document.getElementById('new-dialog').close(); editor.focus();
});
document.getElementById('copy-text').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(getText()); toast('Текст скопирован'); }
  catch { toast('Не удалось скопировать. Выделите текст и нажмите Ctrl+C.'); }
});
document.getElementById('paste-text').addEventListener('click', async () => {
  try {
    const pasted = await navigator.clipboard.readText();
    if (!pasted) { toast('В буфере нет текста'); return; }
    snapshot(); text = pasted; revision++; suggestions = []; checked = false;
    render(); save(); editor.focus();
  } catch { toast('Нажмите на поле текста и вставьте через Ctrl+V.'); }
});
document.getElementById('dictionary-form').addEventListener('submit', event => { event.preventDefault(); addWord(document.getElementById('dictionary-word').value); document.getElementById('dictionary-word').value = ''; });
document.getElementById('dictionary-list').addEventListener('click', event => {
  const button = event.target.closest('[data-remove-word]');
  if (!button) return;
  dictionary.splice(Number(button.dataset.removeWord), 1);
  storage.set('dictionary', dictionary); renderDictionary(); toast('Слово удалено из словаря');
});
document.getElementById('editor-nav').addEventListener('click', () => editor.focus());
document.getElementById('settings-theme').addEventListener('click', () => document.querySelector('[data-theme-toggle]').click());
document.getElementById('model-select').value = storage.get('model', 'GigaChat 3.1 Lightning');
document.getElementById('model-select').addEventListener('change', event => { storage.set('model', event.target.value); toast('Выбор сохранён для макета'); });
document.getElementById('open-setup').addEventListener('click', () => { document.getElementById('settings-dialog').close(); openDialog('setup-dialog'); });
document.addEventListener('keydown', event => {
  if (document.querySelector('dialog[open]')) return;
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') { event.preventDefault(); checkText(); }
});

let setupStep = 0;
let setupTimer;
const setupButton = document.getElementById('setup-next');
const setupProgress = document.getElementById('setup-progress');
function renderSetup() {
  const ids = ['setup-ollama', 'setup-start', 'setup-model', 'setup-ready'];
  ids.forEach((id, index) => {
    const row = document.getElementById(id);
    row.classList.toggle('done', index < setupStep);
    row.querySelector('.step-state').innerHTML = icon(index < setupStep ? 'check' : index === 3 ? 'edit' : index === 1 ? 'refresh' : 'download');
  });
  setupButton.innerHTML = [ `Показать установку ${icon('arrow')}`, `Показать запуск ${icon('arrow')}`, `Показать загрузку модели ${icon('download')}`, `Начать работу ${icon('arrow')}` ][Math.min(setupStep, 3)];
  setupButton.disabled = false;
}
setupButton.addEventListener('click', () => {
  document.getElementById('setup-error-message').hidden = true;
  if (setupStep >= 3) {
    setupStep = 4; renderSetup(); document.getElementById('setup-dialog').close(); toast('Демонстрация завершена. Можно писать.'); return;
  }
  const wrapper = document.querySelector('.setup-progress');
  wrapper.hidden = false;
  setupButton.disabled = true;
  document.getElementById('setup-progress-label').textContent = ['Демонстрация установки Ollama', 'Демонстрация запуска Ollama', 'Демонстрация загрузки модели'][setupStep];
  setupProgress.value = 0;
  document.getElementById('setup-percent').textContent = '0%';
  clearInterval(setupTimer);
  setupTimer = setInterval(() => {
    setupProgress.value = Math.min(100, setupProgress.value + 10);
    document.getElementById('setup-percent').textContent = `${setupProgress.value}%`;
    if (setupProgress.value === 100) {
      clearInterval(setupTimer);
      setupStep++;
      wrapper.hidden = true;
      renderSetup();
    }
  }, 100);
});
document.getElementById('setup-error').addEventListener('click', () => {
  clearInterval(setupTimer);
  setupStep = 2;
  renderSetup();
  document.querySelector('.setup-progress').hidden = true;
  document.getElementById('setup-error-message').hidden = false;
  setupButton.disabled = false;
  setupButton.innerHTML = `Попробовать ещё раз ${icon('refresh')}`;
});
document.getElementById('setup-dialog').addEventListener('close', () => { clearInterval(setupTimer); document.querySelector('.setup-progress').hidden = true; renderSetup(); });
checked = true;
suggestions = findSuggestions();
selectedId = suggestions[0]?.id ?? null;
render(); renderDictionary(); renderSetup();
syncModeIndicator();
document.fonts.ready.then(syncModeIndicator);
window.addEventListener('resize', syncModeIndicator);
animateSuggestions();
