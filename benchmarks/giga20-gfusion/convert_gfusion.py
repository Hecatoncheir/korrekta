"""Потоковая деквантизация официального FP8 в BF16 для загрузки NF4."""

from contextlib import ExitStack
import hashlib
import json
import os
from pathlib import Path
import shutil

os.environ["HF_HOME"] = "E:/korrekta/cache/huggingface"
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TEMP"] = "E:/korrekta/tmp"
os.environ["TMP"] = os.environ["TEMP"]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    import torch
    from safetensors import safe_open
    from safetensors.torch import save_file

    torch.set_num_threads(12)
    protocol = json.loads(Path("benchmarks/giga20-gfusion/protocol-v1.json").read_text(encoding="utf-8"))
    model = protocol["models"][1]
    source = Path("E:/korrekta/cache/huggingface/hub/models--ai-sage--GFusion-10B-A1.8B/snapshots") / model["revision"]
    output = Path("E:/korrekta/gfusion/bf16-96199b4")
    output.mkdir(parents=True, exist_ok=False)
    for weight in model["weights"]:
        path = source / weight["name"]
        if path.stat().st_size != weight["bytes"] or digest(path) != weight["sha256"]:
            raise ValueError(f"Не совпали официальные веса: {path}")
    config = json.loads((source / "config.json").read_text(encoding="utf-8"))
    block_rows, block_columns = config.pop("quantization_config")["weight_block_size"]
    (output / "config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    for path in source.iterdir():
        if path.name not in ["config.json", "model.safetensors.index.json"] and path.suffix in [".json", ".jinja", ".py", ".md"]:
            shutil.copyfile(path, output / path.name)
    original = json.loads((source / "model.safetensors.index.json").read_text(encoding="utf-8"))["weight_map"]
    converted, shard, shard_bytes, total_bytes, files = {}, {}, 0, 0, []

    def save_shard():
        nonlocal shard, shard_bytes
        name = f"model-{len(files) + 1:05d}.safetensors"
        path = output / name
        save_file(shard, path, metadata={"format": "pt"})
        converted.update({key: name for key in shard})
        files.append({"name": name, "bytes": path.stat().st_size, "sha256": digest(path)})
        shard, shard_bytes = {}, 0
        print(f"Сохранён {name}", flush=True)

    with ExitStack() as stack:
        readers = {name: stack.enter_context(safe_open(source / name, framework="pt", device="cpu")) for name in set(original.values())}
        for key in sorted(original):
            if key.endswith("_scale_inv"):
                continue
            tensor = readers[original[key]].get_tensor(key)
            if str(tensor.dtype).startswith("torch.float8"):
                scale_key = key + "_scale_inv"
                scale = readers[original[scale_key]].get_tensor(scale_key)
                if tensor.ndim != 2:
                    raise ValueError(f"Неожиданная форма FP8: {key}")
                rows, columns = tensor.shape
                expanded = scale.repeat_interleave(block_rows, 0).repeat_interleave(block_columns, 1)[:rows, :columns]
                tensor = (tensor.float() * expanded).to(torch.bfloat16)
            tensor = tensor.contiguous().clone()
            size = tensor.numel() * tensor.element_size()
            if shard and shard_bytes + size > 1024 ** 3:
                save_shard()
            shard[key] = tensor
            shard_bytes += size
            total_bytes += size
        if shard:
            save_shard()
    index = {"metadata": {"total_size": total_bytes}, "weight_map": converted}
    (output / "model.safetensors.index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    manifest = {"source_revision": model["revision"], "method": "FP8.float32 * повторённые по блокам 128x128 weight_scale_inv; затем BF16. Остальные тензоры сохранены без изменения значений.", "files": files}
    (output / "conversion.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Готово: {output}", flush=True)


if __name__ == "__main__":
    main()
