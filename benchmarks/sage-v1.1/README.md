# Проверка SAGE v1.1.0

Исследовательский запуск отдельного русского корректора `ai-forever/sage-v1.1.0` на основе FRED-T5-1.7B. Это другие веса, чем у ранее проверенной `sage-fredt5-large`. Интерфейс и прикладная логика приложения остаются на Flutter/Dart; этот Python-запуск нужен только для исследования.

Версии модели, токенизатора, SHA-256 весов, наборы и параметры заморожены в [protocol-v1.json](protocol-v1.json) до получения ответов. Результаты — в [отчёте](../results/2026-11-03/sage-v1.1/README.md).

## Подготовка

Команды выполняются из корня репозитория в ранее подготовленной среде `E:\korrekta\sage-venv`. Версии библиотек не меняются: PyTorch 2.11.0+cu128, Transformers 5.22.1. [Подготовка среды](../sage/README.md).

```powershell
$sagePython = 'E:\korrekta\sage-venv\Scripts\python.exe'
& $sagePython -X utf8 benchmarks/sage-v1.1/download.py
& $sagePython -X utf8 benchmarks/sage/run.py --model ai-forever/sage-v1.1.0 --download
```

Первая команда скачивает только `model.safetensors` (6 961 484 928 байт) диапазонами в четыре потока и проверяет SHA-256 по официальным LFS-метаданным. Проверенные веса переносятся из временного файла в кеш на E:. При оставшемся временном файле команда останавливается, не перезаписывая его. Вторая команда завершает снимок конфигурациями и отдельно скачивает токенизатор FRED-T5-1.7B. Базовые веса FRED и дублирующий `pytorch_model.bin` не загружаются.

## Измерение

```powershell
& $sagePython -X utf8 benchmarks/sage/run.py --model ai-forever/sage-v1.1.0 --data benchmarks/cases-v1.jsonl --split dev --device cuda --output work/sage11-dev.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --model ai-forever/sage-v1.1.0 --data benchmarks/cases-v1.jsonl --split test --device cuda --output work/sage11-test.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --model ai-forever/sage-v1.1.0 --data benchmarks/preservation/cases-v1.jsonl --split test --device cuda --output work/sage11-preservation.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --model ai-forever/sage-v1.1.0 --data benchmarks/gigachat-prompts/holdout-v1.jsonl --split test --device cuda --output work/sage11-holdout.jsonl
& $sagePython -X utf8 benchmarks/sage-v1.1/audit_tokenizer.py --output work/sage11-tokenizer.json
```

Дополнительно проверены `benchmarks/sber-large/layout-smoke-v1.jsonl` (12 текстов) и `benchmarks/paragraphs-v1.jsonl` (3 абзаца), оба со `--split dev`. Всего 415 повторных запросов плюс по одному отдельному первому запросу для каждого из шести запусков. Существующий файл результата не перезаписывается.

Использованы официальный токенизатор FRED-T5-1.7B и префикс `<LM>` из [карточки модели](https://huggingface.co/ai-forever/sage-v1.1.0). FP32, greedy, один луч, seed 42, без усечения входа, предел выхода `max(16, ceil(input_tokens * 1.5))`. Входные пробелы, табуляция, переносы и результат не нормализуются. В частности, демонстрационное сокращение повторных переносов из карточки не применяется: для Корректы это данные автора. После загрузки используется автономный режим библиотек; физическое отключение сети не проверялось.

`audit_tokenizer.py` проверяет дословное восстановление всей строки `<LM>` + исходный текст без генерации. Префикс участвует в сравнении с обеих сторон; из результатов модели он не удаляется. Так можно отличить потери представления текста от изменений при генерации.

## Оценка

Общие метрики вычисляет существующий Dart-инструмент `tools/model_benchmark/bin/compare_texts.dart` (`text-effects-v1`), сохранение фрагментов — `benchmarks/preservation/check_retention.py`. Учитываются все уникальные случаи, совпадение исходников и эталонов, точное исправление без побочных замен и изменения правильных текстов. Счётчик `protected` сравнивает число дословных вхождений и сам по себе не проверяет порядок; полное совпадение итогового текста учитывается отдельно.

Сравнение использует сохранённые результаты прежних движков. Для JSON-предложений GigaChat и LanguageTool это итог после проверки диапазонов, для SAGE и GigaChat text-only — полный выход. Эти пути имеют разную защиту; фильтрация правок SAGE ещё не реализована. Все наборы уже использовались в исследованиях, параметры здесь по ним не подбираются. Результаты не являются новой независимой приёмкой или минимальными требованиями к оборудованию.

Оценки для опубликованного отчёта сохранены как `comparison-dev.json`, `comparison-test.json`, `comparison-preservation.json`, `comparison-holdout.json`, `comparison-layout.json`, `comparison-paragraphs.json`; первым файлом каждого сравнения передаётся соответствующий `sage11-*.jsonl`. Проверка protected сохраняется отдельно для preservation и holdout:

```powershell
python -X utf8 benchmarks/preservation/check_retention.py --data benchmarks/preservation/cases-v1.jsonl --output work/sage11-retention.json benchmarks/results/2026-11-03/sage-v1.1/sage11-preservation.jsonl
python -X utf8 benchmarks/sage-v1.1/summarize.py
```

`summarize.py` проверяет полноту всех шести сохранённых прогонов, исходники, эталоны и замороженные SHA-256 наборов; собирает `overview.json` из готовых оценок и проверок protected. Он не запускает модели и не подбирает параметры. Имена и пути результатов в нём соответствуют сохранённому отчёту.
