# Более крупные локальные модели Сбера

Исследование продолжает M1: три специализированные модели SAGE и дополнительная проверка уже установленного GigaChat 3.1. Размер сам по себе не считается признаком лучшего корректора. [Протокол](protocol-v1.json), [результаты](../results/2026-11-03/sber-large/README.md).

## Кандидаты

| Модель | Задача по официальной карточке | Веса safetensors |
| --- | --- | ---: |
| [sage-fredt5-large](https://huggingface.co/ai-forever/sage-fredt5-large) | Русская орфография и пунктуация, на базе FRED-T5 | 3 282 058 120 байт |
| [sage-m2m100-1.2B](https://huggingface.co/ai-forever/sage-m2m100-1.2B) | Русская орфография, адаптация M2M100 | 4 491 994 792 байта |
| [sage-mt5-large](https://huggingface.co/ai-forever/sage-mt5-large) | Орфография русского и английского, адаптация mT5 | 4 918 393 736 байт |

Это специализированные модели команды ai-forever; архитектуры mT5 и M2M100 исходно разработаны другими авторами. Модели опубликованы с лицензией MIT. В карточках есть отдельные результаты с обозначением `ft` и облачного `sage-ai-service`: они не приписываются проверяемым опубликованным весам. Контрольные суммы и ревизии зафиксированы в `benchmarks/sage/run.py` и проверены перед запуском.

## Подготовка на E:

Из корня проекта, с существующим окружением SAGE:

```powershell
$env:PIP_CACHE_DIR = 'E:\korrekta\cache\pip'
$env:TEMP = 'E:\korrekta\tmp'
$env:TMP = $env:TEMP
& E:\korrekta\sage-venv\Scripts\python.exe -m pip install -r benchmarks/sber-large/requirements.txt
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-fredt5-large --download
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-m2m100-1.2B --download
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-mt5-large --download
```

Загружаются только safetensors и необходимые файлы токенизатора, без второй копии весов `pytorch_model.bin`. Кеш остаётся `E:\korrekta\cache\huggingface`. Если прямая загрузка mT5 медленная, `python -X utf8 benchmarks/sber-large/download_mt5.py` получает тот же официальный файл диапазонами, проверяет размер и SHA-256 и помещает его в кеш. После этого повторите `--download`, чтобы завершить снимок Hugging Face. Ни другая установленная модель, ни глобальные настройки Python/Ollama не заменяются.

## Последовательная проверка

```powershell
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-fredt5-large --data benchmarks/cases-v1.jsonl --split dev --device cuda --output work/fred-dev.jsonl
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-fredt5-large --data benchmarks/cases-v1.jsonl --split test --device cuda --output work/fred-test.jsonl
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sage/run.py --model ai-forever/sage-fredt5-large --data benchmarks/preservation/cases-v1.jsonl --split test --device cuda --output work/fred-preservation.jsonl
```

Для mT5 замените идентификатор модели и пути результатов. Для M2M100 добавьте `--beams 5`: сохранено число лучей из конфигурации авторов, также заданы исходный и целевой язык `ru` и принудительный русский BOS. Остальные варианты используют greedy, один луч. Все новые прогоны SAGE — FP32 на GPU, без дополнительной квантизации и обучения. Это отличается от CPU-замеров SAGE 95M на оформлении; в таблицах сравнивается качество, а устройство и формат ответа при сравнении скорости нужно учитывать отдельно.

Отдельная проба `layout-smoke-v1.jsonl` содержит 8 ошибок раскладки и 4 правильных технических фразы из предыдущей быстрой проверки. Её запускают как `--split dev`. Это маленькая диагностическая проба, не доказательство поддержки или отсутствия поддержки всех ошибок раскладки.

## GigaChat и подача диалога

Используются прежние веса `hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M`, Ollama 0.40.13 и отдельный локальный сервер на `127.0.0.1:11435`. Облачные запросы отключены. Запускайте только один движок на GPU; между моделями выгружайте предыдущую.

Дополнительный режим `raw` готовит запрос официальным шаблоном из [репозитория токенизатора](https://huggingface.co/ai-sage/GigaChat3.1-10B-A1.8B-bf16/tree/189fff27a1dee68473960c3d5bca53e0e07a3191). Скачиваются только токенизатор и шаблон, без BF16-весов:

```powershell
& E:\korrekta\sage-venv\Scripts\python.exe -X utf8 benchmarks/sber-large/render_gigachat.py --data benchmarks/cases-v1.jsonl --output work/gigachat-native-cases.jsonl
```

Из `tools/model_benchmark`:

```powershell
dart run bin/benchmark.dart --model hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M --endpoint http://127.0.0.1:11435 --raw --data ../../work/gigachat-native-cases.jsonl --prompt ../../benchmarks/prompt-v1.txt --split dev --output ../../work/gigachat-native-dev.jsonl
```

`--raw` отправляет `rendered_prompt` в `/api/generate` с `raw=true`, без второго наложения шаблона; структура JSON и проверка правок прежние. Контрольный обычный режим — без `--raw`, с исходным набором, через `/api/chat`. Эти варианты подают запрос по-разному: Python-рендерер использует JSON с пробелом после двоеточия, Dart — компактный JSON. В текущем `/api/show` Jinja совпал с официальным по SHA-256, тогда как старый отчёт сохранял `{{ .Prompt }}`. Поэтому наблюдаемую разницу результатов нельзя причинно объяснять только исправлением шаблона. Все новые результаты сохраняются отдельно от первого исследования.

## Оценка

`compare_texts.dart` оценивает одинаковые итоговые тексты через `text-effects-v1`; `benchmarks/preservation/check_retention.py` проверяет защищённые фрагменты. Команды и определения метрик описаны в [проверке сохранения текста](../preservation/README.md). После формирования `comparison-test.json`, `comparison-preservation.json` и `retention.json` команда `python -X utf8 benchmarks/sber-large/summarize.py` создаёт компактную сводку `overview.json`.

Наборы уже использованы в исследовании. Параметры не настраиваются по ответам test; окончательное подтверждение качества требует новых независимых текстов после выбора всей схемы проверки, включая фильтры.
