"""Кеш общей части инструкции без изменения официального декодирования."""


def prepare_prefix_cache(model, tokenized_inputs):
    import torch
    from transformers.cache_utils import DynamicCache
    from transformers.modeling_outputs import CausalLMOutputWithPast

    common = tokenized_inputs[0].tolist()
    for tokens in tokenized_inputs[1:]:
        length = 0
        for left, right in zip(common, tokens.tolist()):
            if left != right:
                break
            length += 1
        common = common[:length]
    # Совпадают только полные блоки, которые официальный generate префиллит отдельно.
    length = len(common) // 32 * 32
    if not length:
        return model.forward, {"prefix_tokens": 0, "cpu_bytes": 0}
    original = model.forward
    cache = None
    with torch.inference_mode():
        for start in range(0, length, 32):
            ids = torch.tensor([common[start:start + 32]], device="cuda")
            positions = torch.arange(start, start + 32, device="cuda").unsqueeze(0)
            result = original(input_ids=ids, position_ids=positions, use_cache=True, update_dllm_cache=True, past_key_values=cache, return_dict=True)
            cache = result.past_key_values
    saved = tuple((keys.cpu(), values.cpu()) for keys, values in cache.to_legacy_cache())
    del result, cache
    cpu_bytes = sum(tensor.numel() * tensor.element_size() for pair in saved for tensor in pair)

    def forward(*args, **kwargs):
        positions = kwargs.get("position_ids")
        if kwargs.get("use_cache") and kwargs.get("update_dllm_cache") and positions is not None:
            start = int(positions[0, 0].item())
            ids = kwargs["input_ids"]
            if start < length:
                if ids.shape[1] != 32 or ids[0].tolist() != common[start:start + 32]:
                    raise ValueError("Запрос не совпал с кешированным префиксом")
                if start == 0:
                    ready = DynamicCache.from_legacy_cache(tuple((keys.to("cuda"), values.to("cuda")) for keys, values in saved))
                else:
                    ready = kwargs["past_key_values"]
                return CausalLMOutputWithPast(past_key_values=ready)
        return original(*args, **kwargs)

    return forward, {"prefix_tokens": length, "cpu_bytes": cpu_bytes}
