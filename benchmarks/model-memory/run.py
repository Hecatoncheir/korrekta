"""Контролируемое сравнение качества и наблюдаемой памяти локальных моделей."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'benchmarks/results/2026-11-04/model-memory'
DART = r'C:\Users\vostr\code\flutter\bin\dart.bat'
ENDPOINT = 'http://127.0.0.1:11435/api/'
BIG = 'hf.co/ai-sage/GigaChat-20B-A3B-instruct-v1.5-GGUF:Q4_K_M'
SMALL = 'hf.co/ai-sage/GigaChat3.1-10B-A1.8B-GGUF:Q4_K_M'


def read(path):
    return [json.loads(s) for s in path.read_text(encoding='utf-8').splitlines() if s.strip()]


def digest(path):
    return hashlib.sha256(path.read_text(encoding='utf-8').encode()).hexdigest()


def save(path, value):
    if path.exists():
        assert json.loads(path.read_text(encoding='utf-8')) == value, path
    else:
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def api(method, data=None):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(ENDPOINT + method, data=body, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def unload():
    for model in api('ps')['models']:
        api('generate', {'model': model['name'], 'keep_alive': 0})
    for _ in range(30):
        if not api('ps')['models']:
            return
        time.sleep(.2)
    raise RuntimeError('Модель не выгрузилась')


def gpu_memory():
    result = subprocess.check_output(['nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader,nounits'],
        text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    return float(result.splitlines()[0])


def process_memory(psutil, root_pid, children=True):
    try:
        root = psutil.Process(root_pid)
        family = [root, *root.children(recursive=True)] if children else [root]
    except psutil.Error:
        return {'rss': 0, 'private': 0, 'processes': []}
    values = []
    for process in family:
        try:
            memory = process.memory_info()
            values.append({'pid': process.pid, 'name': process.name(), 'rss': memory.rss,
                           'private': getattr(memory, 'private', memory.vms)})
        except psutil.Error:
            pass
    return {'rss': sum(v['rss'] for v in values), 'private': sum(v['private'] for v in values), 'processes': values}


def monitor(stop, child_pid, ollama_pid, lt_pid, target):
    import psutil
    with target.open('x', encoding='utf-8') as sink:
        while not stop.is_set():
            sample = {'utc': datetime.now(timezone.utc).isoformat(), 'gpu_mib': gpu_memory(),
                'ollama': process_memory(psutil, ollama_pid), 'dart': process_memory(psutil, child_pid),
                'languagetool': process_memory(psutil, lt_pid, False)}
            sink.write(json.dumps(sample) + '\n')
            sink.flush()
            stop.wait(.5)


def freeze():
    assert not (HERE / 'protocol-v1.json').exists()
    prepared = json.loads((OUT / 'preparation.json').read_text(encoding='utf-8'))
    assert prepared['10b']['max_prompt_tokens'] + 1024 > 2048
    profiles = [
        {'id': '20b-8k', 'model': BIG, 'key': '20b', 'context': 8192},
        {'id': '10b-8k', 'model': SMALL, 'key': '10b', 'context': 8192},
        {'id': '10b-4k', 'model': SMALL, 'key': '10b', 'context': 4096},
        {'id': '20b-4k', 'model': BIG, 'key': '20b', 'context': 4096},
        {'id': '20b-2k', 'model': BIG, 'key': '20b', 'context': 2048},
    ]
    paths = [HERE / 'run.py', HERE / 'prepare.py', ROOT / 'tools/model_benchmark/bin/ensemble_memory.dart',
        OUT / '20b-input.jsonl', OUT / '10b-input.jsonl', OUT / 'preparation.json', ROOT / 'benchmarks/best-known.json',
        ROOT / 'benchmarks/gigachat-prompts/text-json.txt']
    paths += list((ROOT / 'tools/model_benchmark/lib').rglob('*.dart'))
    weights = {}
    for name in ['GigaChat-20B-A3B-instruct-v1.5-GGUF', 'GigaChat3.1-10B-A1.8B-GGUF']:
        path = Path('E:/ollama/models/manifests/hf.co/ai-sage') / name / 'Q4_K_M'
        manifest = json.loads(path.read_text())
        layer = next(v for v in manifest['layers'] if v['mediaType'].endswith('.model'))
        blob = Path('E:/ollama/models/blobs') / layer['digest'].replace(':', '-')
        assert blob.stat().st_size == layer['size']
        weights[name] = layer
    save(HERE / 'protocol-v1.json', {'created_utc': datetime.now(timezone.utc).isoformat(),
        'baseline_commit': 'eb5256d87a3c6b3e7aa4e9f08a046b78254312c2', 'profiles': profiles, 'weights': weights,
        'data': '143 знакомых текста: фиксированные140 (60 ошибок/80 контролей) + 3 прежних абзаца; не новая независимая приёмка. Все генерации новые, промпт и inflections неизменны. Официальные шаблоны каждой модели, лимит ответа1024, temp0/seed42.',
        'decision': 'Потеря не более3 чистых из60 относительно нового одновременного 20b-8k, без роста изменённых контролей/protected/atomic_fp/сбоев; абзацы не хуже по clean/atomic_fp. Среди прошедших сравнить память. Это заранее принятый рабочий допуск5 процентных пунктов, не универсальное определение некритичности. Эталон20B сохранить независимо от экономичного профиля.',
        'memory': 'Каждые примерно0.5-1с: суммарная занятая GPU Nvidia; текущий RSS и private bytes семьи собственного Ollama, Dart и существующего LT отдельно. Это наблюдавшийся максимум выборки, не точный CUDA peak и не минимальные требования. RSS семей может повторно учитывать общие страницы; private не равно физической RAM. Холодная загрузка модели отдельно, файловый кеш ОС не сбрасывается.',
        'sha256_lf': {str(p.relative_to(ROOT)).replace('\\', '/'): digest(p) for p in sorted(paths)}})
    print('Пять конфигураций и критерии зафиксированы до первого запроса.')


def verify():
    protocol = json.loads((HERE / 'protocol-v1.json').read_text(encoding='utf-8'))
    for path, sha in protocol['sha256_lf'].items():
        assert digest(ROOT / path) == sha, path
    return protocol


def run(profile, ollama_pid, lt_pid):
    output = OUT / f"{profile['id']}.jsonl"
    assert not output.exists(), output
    unload()
    idle = gpu_memory()
    print('Начало', profile['id'], 'GPU до загрузки', idle, flush=True)
    command = [DART, 'run', 'bin/ensemble_memory.dart', '--input', str(OUT / f"{profile['key']}-input.jsonl"),
        '--output', str(output), '--model', profile['model'], '--context', str(profile['context']),
        '--prompt', str(ROOT / 'benchmarks/gigachat-prompts/text-json.txt')]
    process = subprocess.Popen(command, cwd=ROOT / 'tools/model_benchmark', stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding='utf-8', creationflags=subprocess.CREATE_NO_WINDOW)
    stop = threading.Event()
    samples = OUT / f"{profile['id']}-samples.jsonl"
    thread = threading.Thread(target=monitor, args=(stop, process.pid, ollama_pid, lt_pid, samples))
    thread.start()
    try:
        for line in process.stdout:
            print(line.rstrip(), flush=True)
        code = process.wait()
    finally:
        stop.set()
        thread.join()
    assert code == 0, code
    rows = read(output)
    assert rows[-1]['completed']
    resident = rows[-1]['resident']['models']
    assert len(resident) == 1 and resident[0]['name'] == profile['model'] and resident[0]['context_length'] == profile['context']
    measured = read(samples)
    assert measured
    save(OUT / f"{profile['id']}-resources.json", {'gpu_idle_mib': idle,
        'gpu_observed_peak_mib': max(r['gpu_mib'] for r in measured), 'samples': len(measured),
        'ollama_rss_observed_peak': max(r['ollama']['rss'] for r in measured),
        'ollama_private_observed_peak': max(r['ollama']['private'] for r in measured),
        'dart_rss_observed_peak': max(r['dart']['rss'] for r in measured),
        'lt_rss_observed_peak': max(r['languagetool']['rss'] for r in measured),
        'resident': resident[0]})
    unload()
    print('Завершено', profile['id'], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=['freeze', 'check', 'run'], required=True)
    parser.add_argument('--ollama-pid', type=int)
    parser.add_argument('--lt-pid', type=int)
    args = parser.parse_args()
    if args.phase == 'freeze':
        freeze()
        return
    protocol = verify()
    if args.phase == 'check':
        print('Проверены замороженные данные и исходники; модель не запускалась.')
        return
    assert args.ollama_pid and args.lt_pid
    try:
        for profile in protocol['profiles']:
            run(profile, args.ollama_pid, args.lt_pid)
    finally:
        unload()


if __name__ == '__main__':
    main()
