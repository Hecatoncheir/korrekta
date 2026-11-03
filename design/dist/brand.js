const variants = [
  { svg: mark, caption: '<strong>01 / Росчерк.</strong> Мягкая буква «к» из трёх движений пера. Нижний штрих похож на отметку корректора. Основной вариант для сайта и приложения.' },
  { svg: '<svg viewBox="0 0 100 100" aria-hidden="true"><path d="M24 12C7 12 8 35 15 50L34 87c3 6 12 2 9-4L30 48c19-2 24-36-6-36Zm50 0C57 12 58 35 65 50L84 87c3 6 12 2 9-4L80 48c19-2 24-36-6-36Z" fill="currentColor"/></svg>', caption: '<strong>02 / Кавычки.</strong> Два знака препинания складываются в пару дружелюбных росчерков. Акцент на авторском голосе и внимании к чужим словам.' },
  { svg: '<svg viewBox="0 0 100 100" aria-hidden="true"><path d="M56 7C40 14 10 37 10 58c0 24 17 35 40 35s40-16 40-36C90 36 73 17 56 7Z" fill="currentColor"/><path d="m30 53 15 15 27-31" fill="none" stroke="var(--swatch-bg,#fbf1c7)" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/></svg>', caption: '<strong>03 / Чернильная точка.</strong> Органичная капля с отметкой внутри. Самый предметный вариант: чернила, завершённая мысль и принятая правка.' }
];
function setVariant(index) {
  const item = variants[index];
  document.getElementById('variant-light').innerHTML = item.svg;
  document.getElementById('variant-dark').innerHTML = item.svg;
  document.getElementById('variant-dark').style.setProperty('--swatch-bg', '#282828');
  document.getElementById('variant-caption').innerHTML = item.caption;
  document.querySelectorAll('[data-variant]').forEach(button => button.setAttribute('aria-pressed', Number(button.dataset.variant) === index));
}
document.querySelectorAll('[data-variant]').forEach(button => button.addEventListener('click', () => setVariant(Number(button.dataset.variant))));
setVariant(0);
