const examples = [
  { html: 'Мне <span class="error-underline">нравиться</span> писать.<br>Особенно когда слова находят<br>своё место.', original: 'нравиться', replacement: 'нравится', category: 'ГРАММАТИКА' },
  { html: '<span class="error-underline">Кажется это</span> начало<br>хорошей истории.<br>Осталось её записать.', original: 'Кажется это', replacement: 'Кажется, это', category: 'ПУНКТУАЦИЯ' },
  { html: 'Иногда достаточно<br><span class="error-underline">по настоящему</span> точного слова,<br>чтобы всё стало ясно.', original: 'по настоящему', replacement: 'по-настоящему', category: 'ОРФОГРАФИЯ' }
];
let exampleIndex = 0;
let accepted = false;
document.getElementById('demo-apply').addEventListener('click', () => {
  if (accepted) {
    exampleIndex = (exampleIndex + 1) % examples.length;
    const example = examples[exampleIndex];
    document.getElementById('demo-text').innerHTML = example.html;
    document.getElementById('demo-change').innerHTML = `<del>${example.original}</del>${icon('arrow')}<ins>${example.replacement}</ins>`;
    document.getElementById('demo-category').textContent = example.category;
    document.getElementById('demo-status').textContent = 'Одно исправление';
    document.querySelector('.demo-caption .mono').textContent = `0${exampleIndex + 1} / 03`;
    document.getElementById('demo-apply').setAttribute('aria-label', 'Применить исправление');
    document.getElementById('demo-apply').innerHTML = icon('check');
    accepted = false;
    return;
  }
  const text = document.querySelector('#demo-text .error-underline');
  text.textContent = examples[exampleIndex].replacement;
  text.classList.add('corrected');
  document.getElementById('demo-category').textContent = 'ТЕПЕРЬ ВСЁ В ПОРЯДКЕ';
  document.getElementById('demo-status').textContent = 'Исправлено';
  document.getElementById('demo-apply').innerHTML = icon('arrow');
  document.getElementById('demo-apply').setAttribute('aria-label', 'Следующий пример');
  accepted = true;
});
document.querySelectorAll('.platforms button').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('.platforms button').forEach(item => item.setAttribute('aria-pressed', item === button));
  document.getElementById('platform-title').textContent = `Планируется для ${button.textContent}`;
}));
