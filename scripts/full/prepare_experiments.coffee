path = require 'path'

@step =
  desc: "Materialize experiments.csv for MLX LoRA training"

  action: (S) ->
    contract = await S.need 'data_contract'
    catalog  = await S.need 'data_catalog'
    report   = await S.need 'data_report'

    outputDir      = S.param 'output_dir'
    dataDir        = S.param 'data_dir'
    modelId        = S.param 'model'
    epochs         = parseInt S.param 'epochs'
    batchSize      = parseInt S.param 'batch_size'
    gradAccum      = parseInt S.param 'grad_accum'
    maxSeqLength   = parseInt S.param 'max_seq_length'
    learningRate   = parseFloat S.param 'learning_rate'
    bf16           = if S.param('bf16') then 1 else 0
    itersOverride  = parseInt S.param 'iters_override'

    trainCount = parseInt(catalog?.entries?.train?.stats?.num_valid_examples ? report?.splits?.train?.valid_examples ? 0)
    validCount = parseInt(catalog?.entries?.valid?.stats?.num_valid_examples ? report?.splits?.valid?.valid_examples ? 0)

    estIters = Math.ceil(
      (Math.max(1, epochs) * Math.max(1, trainCount)) /
      Math.max(1, batchSize * gradAccum)
    )
    iters = if itersOverride > 0 then itersOverride else Math.max(10000, estIters)

    modelTag = modelId.replace /\//g, '--'
    adapterPath = path.join outputDir, modelTag, 'adapter'
    logsDir = path.join outputDir, modelTag, 'logs'

    row =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      model_id: modelId
      data_dir: dataDir
      train_file: contract?.filenames?.train?.resolved ? path.join(dataDir, 'train.jsonl')
      valid_file: contract?.filenames?.valid?.resolved ? path.join(dataDir, 'valid.jsonl')
      train_examples: trainCount
      valid_examples: validCount
      epochs: epochs
      iters: iters
      batch_size: batchSize
      grad_accum: gradAccum
      max_seq_length: maxSeqLength
      learning_rate: learningRate
      bf16: bf16
      adapter_path: adapterPath
      log_dir: logsDir
      est_tokens: maxSeqLength * batchSize * gradAccum * iters

    headers = Object.keys row
    csv = headers.join(',') + "\n" + headers.map((k) -> String(row[k])).join(',') + "\n"

    S.make 'experiments_csv', csv
    S.saveThis 'prepare_experiments:last_row', row
    S.done()
    return
