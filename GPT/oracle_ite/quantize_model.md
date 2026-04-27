Step: `quantize_model`
Recipe: `oracle_ite`

Purpose:
- build the small oracle MLX model in `build/model4` from `build/model`

Inputs:
- params `source_model_dir`, `quantized_model_dir`, `quantized_model_memo_key`
- param object `mlx`

Outputs:
- meta write `quantizedModelDir`
- filesystem output `build/model4`

Quantization contract:
- this step must perform real MLX quantization, not just format conversion
- active `oracle_ite` uses:
  - `mlx.quantize: null`
  - `mlx.q-bits: 4`

Validation:
- if q-bits are requested, an existing target directory is only valid when `config.json` contains quantization metadata
- a converted-only `build/model4` must be rejected and rebuilt

Known pitfalls:
- `--q` is ambiguous in the installed MLX CLI; use `--quantize`
- a converted-only `build/model4` can be around 7.5G and will OOM the oracle
- the historically good oracle model is the genuinely quantized small model, not the convert-only artifact
- multimodal Gemma 4 checkpoints such as `google/gemma-4-E2B-it` are not "small" for this local conversion path; the HF download can contain a single `model.safetensors` shard above the Metal 4 GiB buffer limit and `mlx_lm convert` will fail before quantization completes
- when that happens, prefer a smaller text-only model or a pre-converted MLX model directory instead of local HF-to-MLX conversion
