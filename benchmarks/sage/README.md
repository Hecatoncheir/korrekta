# Локальная проверка SAGE

Исследовательский запуск `ai-forever/sage-fredt5-distilled-95m` через Transformers/PyTorch. Это отдельная модель seq2seq: на входе исходная фраза, на выходе исправленный текст. Инструкции для чата, JSON и объяснения ей не передаются. HTML-прототип к ней не подключён; интерфейс и прикладная логика будущего приложения остаются на Flutter/Dart.

Версия весов и параметры зафиксированы в [protocol-v1.json](protocol-v1.json). [Карточка модели](https://huggingface.co/ai-forever/sage-fredt5-distilled-95m) описывает исправление орфографии и пунктуации, лицензию MIT и пример запуска. Для исследования используется FP32 без квантизации и дообучения. [Результаты](../results/2026-11-03/sage/README.md).

`run.py` также поддерживает три более крупные SAGE через `--model` и число лучей через `--beams`; без этих параметров сохраняется SAGE 95M с одним лучом. Для M2M100 задаются языковые токены `ru`. Дополнительные зависимости, версии весов и команды описаны в [исследовании крупных моделей](../sber-large/README.md). Перед загрузкой в память проверяется SHA-256 весов; в новых прогонах `load_seconds` включает эту проверку.

Для `ai-forever/sage-v1.1.0` используются отдельный токенизатор FRED-T5-1.7B и префикс `<LM>`; прежний режим 95M по умолчанию сохранён. [Подготовка и протокол этой версии](../sage-v1.1/README.md).

## Подготовка на Windows

Команды выполняются из корня репозитория. Нужен Python 3.13 x64. Большие зависимости, временные файлы, кеши и веса направлены на E:. Системный Python, Ollama и существующие модели не заменяются.

```powershell
New-Item -ItemType Directory -Force E:\korrekta\tmp | Out-Null
$env:TEMP = 'E:\korrekta\tmp'
$env:TMP = $env:TEMP
$env:PIP_CACHE_DIR = 'E:\korrekta\cache\pip'
python -m venv E:\korrekta\sage-venv
$sagePython = 'E:\korrekta\sage-venv\Scripts\python.exe'
& $sagePython -m pip install -r benchmarks/sage/requirements.txt
& $sagePython -X utf8 benchmarks/sage/run.py --download
```

`requirements.txt` фиксирует основные библиотеки и сборку CUDA 12.8 для измерений на RTX 3080 Ti. Полный состав проверенного окружения находится в `requirements-windows.lock.txt`; его можно использовать вместо `requirements.txt` с тем же дополнительным индексом PyTorch. Для CPU использовалась та же сборка, но модель и входные данные размещались только в RAM. Более компактная установка с CPU-сборкой здесь не проверялась.

Веса сохраняются в `E:\korrekta\cache\huggingface\hub\models--ai-forever--sage-fredt5-distilled-95m`. `run.py` задаёт пути кешей до импорта библиотек. Сеть используется только с `--download`; последующие запуски включают `HF_HUB_OFFLINE=1` и `local_files_only=True`. Это проверка программного автономного режима, физическое отключение сети не выполнялось.

## Измерение

```powershell
& $sagePython -X utf8 benchmarks/sage/run.py --data benchmarks/cases-v1.jsonl --split dev --device cuda --output work/sage-dev.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --data benchmarks/cases-v1.jsonl --split test --device cuda --output work/sage-test.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --data benchmarks/cases-v1.jsonl --split dev --device cpu --output work/sage-cpu-dev.jsonl
& $sagePython -X utf8 benchmarks/sage/run.py --data benchmarks/paragraphs-v1.jsonl --split dev --device cpu --output work/sage-cpu-paragraphs.jsonl
```

Повторить последний запуск с `--device cuda` для профиля длины на GPU. Существующий файл не перезаписывается. Первый запрос записывается отдельно как `cold_start`, затем повторяется в общем наборе. Таймер включает токенизацию, вычисления, синхронизацию GPU и декодирование; оценка и запись файла исключены. `load_seconds` включает чтение весов и перенос на устройство, но исключает импорт Python-библиотек и скачивание. Окончание прогона подтверждается успешным завершением процесса и наличием всех уникальных `case` выбранного набора: 40, 160 или 3. Незавершённые файлы не использовать как полный результат.

Сохраняются сырые выходы без нормализации, число токенов, завершение EOS, RAM процесса и память, учтённая аллокатором PyTorch. Последняя не включает всю память драйвера и CUDA. `max_length` следует примеру авторов: 1,5 длины входа, округление вверх, минимум 16. Ничего не обрезается на входе. В проверенных прогонах лимит генерации не исчерпан.

## Общая оценка с Ollama

Из `tools/model_benchmark`:

```powershell
dart run bin/compare_texts.dart ../../benchmarks/results/2026-11-03/sage/sage95m-cuda-test.jsonl ../../benchmarks/results/2026-11-03/ollama-0.40.13/gigachat-test.jsonl ../../benchmarks/results/2026-11-03/ollama-0.40.13/qwen35-4b-test.jsonl ../../benchmarks/results/2026-11-03/ollama-0.40.13/qwen35-9b-test.jsonl
```

Команда выводит JSON в stdout, не запускает модели и проверяет совпадение идентификаторов, исходных текстов и эталонов всех файлов. Метод `text-effects-v1` сравнивает итоговый текст через тот же Unicode LCS diff на Dart. Единица атомарной точности — непрерывный изменённый участок diff, единица полноты исправлений — эталонная ошибка целиком. Необязательные замены ё, кавычек и оформления считаются лишними. Для Ollama берётся сохранённый итог после отклонения недопустимых фрагментов; ошибки структуры и отклонённые предложения учитываются в первоначальном отчёте отдельно.

Это дополнительная общая метрика. Она не заменяет точность карточек правок из первого протокола и не изменяет первоначальные результаты. Строгий diff зависит от выравнивания и эталона; допустимые альтернативные формулировки могут быть оштрафованы. После выбора модели по этому набору окончательная приёмка требует новых независимых примеров.
