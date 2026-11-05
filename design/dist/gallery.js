const slides = [
  { id: 'checking', image: 'checking.png', title: 'Замечает ошибки. Оставляет выбор вам.', description: '«Мне нравиться читать.» → «Мне нравится читать.» Ошибка выделена в тексте, а предложение по исправлению — справа.', alt: 'Ошибка выделена в редакторе; справа показан вариант исправления', label: 'Проверка текста' },
  { id: 'corrections', image: 'corrections.png', title: 'Принять правку. Или вернуться к своему варианту.', description: 'Исправленный фрагмент отмечен зелёным. Если замена не подошла, её можно отменить одним нажатием.', alt: 'Принятая правка выделена зелёным в тексте, внизу доступна отмена', label: 'Принятие правок' },
  { id: 'translation', image: 'translation.png', title: 'Два языка. Одно окно.', description: 'Оригинал слева, перевод справа. Выберите языки, переведите текст локально и скопируйте результат.', alt: 'Русский оригинал и английский перевод в соседних областях приложения', label: 'Перевод текста' },
  { id: 'generation', image: 'generation.png', title: 'Опишите мысль — получите первый вариант.', description: 'Запрос слева, готовый текст справа. В примере — приглашение на прогулку. Генерация готовится к следующему выпуску; в v0.1.7 этого раздела ещё нет.', alt: 'Запрос на приглашение в парк и сгенерированный текст, Vim mode расположен под запросом', label: 'Генерация текста', upcoming: true },
  { id: 'settings', image: 'settings.png', title: 'Всё нужное — на вашем компьютере.', description: 'Выберите локальную модель, добавьте имена и термины в личный словарь. Подключение компонентов и обновления собраны в настройках.', alt: 'Настройки личного словаря, локальных компонентов и выбора модели 10В или 20В', label: 'Настройки' },
  { id: 'light', image: 'light.png', title: 'Светлая или тёмная. Обе — Gruvbox.', description: 'Тёплый фон, спокойные цвета и заметные правки. Тему можно переключить в любой момент; ваш выбор сохраняется.', alt: 'Редактор Корректы в светлой теме Gruvbox с выделенной ошибкой', label: 'Светлая тема' }
];
const tabs = [...document.querySelectorAll('[data-slide]')];
const image = document.getElementById('gallery-image');
const zoom = document.getElementById('zoom-image');
let activeSlide = 0;

function selectSlide(index, focus = false) {
  activeSlide = (index + slides.length) % slides.length;
  const slide = slides[activeSlide];
  for (const tab of tabs) {
    const selected = tab.dataset.slide === slide.id;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
  }
  image.src = `assets/screenshots/${slide.image}`;
  image.alt = slide.alt;
  zoom.src = image.src;
  zoom.alt = slide.alt;
  document.getElementById('zoom-title').textContent = slide.label;
  document.getElementById('gallery-title').textContent = slide.title;
  document.getElementById('gallery-description').textContent = slide.description;
  document.getElementById('gallery-status').textContent = slide.upcoming ? 'Готовится к выпуску' : 'В приложении';
  document.getElementById('gallery-count').textContent = `${String(activeSlide + 1).padStart(2, '0')} / 06`;
  document.getElementById('gallery-panel').setAttribute('aria-labelledby', `tab-${slide.id}`);
  history.replaceState(null, '', `#${slide.id}`);
  if (focus) {
    tabs[activeSlide].focus();
    tabs[activeSlide].scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }
}

tabs.forEach((tab, index) => tab.addEventListener('click', () => selectSlide(index)));
document.querySelector('.gallery-tabs').addEventListener('keydown', event => {
  const destinations = { ArrowLeft: activeSlide - 1, ArrowRight: activeSlide + 1, Home: 0, End: slides.length - 1 };
  if (!(event.key in destinations)) return;
  event.preventDefault();
  selectSlide(destinations[event.key], true);
});
document.getElementById('gallery-previous').addEventListener('click', () => selectSlide(activeSlide - 1));
document.getElementById('gallery-next').addEventListener('click', () => selectSlide(activeSlide + 1));
document.getElementById('screenshot-dialog').addEventListener('keydown', event => {
  if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
  event.preventDefault();
  selectSlide(activeSlide + (event.key === 'ArrowRight' ? 1 : -1));
});
image.addEventListener('load', () => {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  image.animate([{ opacity: .35 }, { opacity: 1 }], { duration: 260, easing: 'ease-out' });
});
const initial = slides.findIndex(slide => `#${slide.id}` === location.hash);
selectSlide(initial < 0 ? 0 : initial);

function feedText(tag, text) {
  const element = document.createElement(tag);
  element.textContent = text;
  return element;
}

function feedFigure(slide, index) {
  const figure = document.createElement('figure');
  figure.id = `example-${slide.id}`;
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'feed-image';
  button.setAttribute('aria-label', `Увеличить скриншот: ${slide.label}`);
  const screenshot = document.createElement('img');
  Object.assign(screenshot, {
    src: `assets/screenshots/${slide.image}`, alt: slide.alt,
    width: 1280, height: 800, loading: index === 0 ? 'eager' : 'lazy'
  });
  button.append(screenshot);
  button.addEventListener('click', () => {
    selectSlide(index);
    document.getElementById('screenshot-dialog').showModal();
  });
  const caption = document.createElement('figcaption');
  caption.className = 'feed-caption';
  if (slide.upcoming) {
    const status = feedText('span', 'Готовится к выпуску');
    status.className = 'pill';
    caption.append(status);
  }
  caption.append(feedText('h2', slide.title), feedText('p', slide.description));
  figure.append(button, caption);
  return figure;
}

document.querySelector('.gallery-feed').append(...slides.map(feedFigure));
document.documentElement.classList.add('gallery-feed-ready');
if (initial >= 0 && matchMedia('(max-width: 760px)').matches) {
  document.getElementById(`example-${slides[initial].id}`).scrollIntoView();
}
