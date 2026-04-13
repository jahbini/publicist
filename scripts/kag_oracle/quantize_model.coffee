fs = require 'fs'
path = require 'path'

listFiles = (rootDir) ->
  out = []

  walk = (currentDir) ->
    for name in fs.readdirSync(currentDir)
      fullPath = path.join(currentDir, name)
      stat = fs.statSync(fullPath)
      if stat.isDirectory()
        walk fullPath
      else
        out.push path.relative(rootDir, fullPath)

  walk rootDir
  out

inspectMLXModelDir = (modelDir) ->
  return { valid: false, reason: 'missing directory' } unless fs.existsSync(modelDir)
  return { valid: false, reason: 'not a directory' } unless fs.statSync(modelDir).isDirectory()

  files = listFiles modelDir
  hasConfig = files.includes 'config.json'
  hasTokenizer = files.includes('tokenizer.json') or files.includes('tokenizer.model')
  hasWeights = files.some (fileName) -> /\.safetensors$/.test(fileName)

  missing = []
  missing.push 'config.json' unless hasConfig
  missing.push 'tokenizer.json|tokenizer.model' unless hasTokenizer
  missing.push '*.safetensors' unless hasWeights

  return {
    valid: missing.length is 0
    reason: if missing.length then "missing #{missing.join(', ')}" else 'ok'
  }

readConfig = (modelDir) ->
  configPath = path.join modelDir, 'config.json'
  return null unless fs.existsSync configPath
  try
    JSON.parse fs.readFileSync(configPath, 'utf8')
  catch
    null

inspectQuantizedModelDir = (modelDir, qBitsRequested) ->
  baseState = inspectMLXModelDir modelDir
  return baseState unless baseState.valid
  return baseState unless qBitsRequested

  config = readConfig modelDir
  quantization = config?.quantization
  return { valid: false, reason: 'missing config.json quantization metadata' } unless quantization? and typeof quantization is 'object'

  return {
    valid: true
    reason: 'ok'
  }

@step =
  desc: "Quantize the laptop oracle MLX model into build/model4"

  action: (S) ->
    sourceParam = S.param 'source_model_dir', 'build/model'
    targetParam = S.param 'quantized_model_dir', 'build/model4'
    memoKey = S.param 'quantized_model_memo_key', 'quantizedModelDir'
    mlxConfig = S.param 'mlx', null
    throw new Error "[quantize_model] mlx must be an object when provided" if mlxConfig? and (typeof mlxConfig isnt 'object' or Array.isArray(mlxConfig))

    sourceDir = path.resolve sourceParam
    targetDir = path.resolve targetParam
    qBitsRequested = Number.isFinite(Number(mlxConfig?['q-bits'])) and Number(mlxConfig['q-bits']) > 0

    sourceState = inspectMLXModelDir sourceDir
    throw new Error "[quantize_model] source model invalid at #{sourceDir}: #{sourceState.reason}" unless sourceState.valid

    targetState = inspectQuantizedModelDir targetDir, qBitsRequested
    if targetState.valid
      console.log "[quantize_model] quantized model already exists, skipping"
      S.saveThis memoKey, targetDir
      S.done()
      return

    if fs.existsSync(targetDir)
      console.log "[quantize_model] removing invalid existing #{targetParam}"
      fs.rmSync targetDir, recursive: true, force: true

    fs.mkdirSync path.dirname(targetDir), recursive: true

    console.log "[quantize_model] creating #{targetParam} from #{sourceParam}"
    convertArgs =
      "hf-path": sourceDir
      "mlx-path": targetDir
    if mlxConfig? and typeof mlxConfig is 'object'
      for own key, value of mlxConfig
        continue unless value?
        convertArgs[key] = value
    S.callMLX 'convert', convertArgs

    finalState = inspectQuantizedModelDir targetDir, qBitsRequested
    throw new Error "[quantize_model] quantized model invalid at #{targetDir}: #{finalState.reason}" unless finalState.valid

    console.log "[quantize_model] quantization complete"
    S.saveThis memoKey, targetDir
    S.done()
    return
