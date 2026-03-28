path = require 'path'
crypto = require 'crypto'

@step =
  desc: "Register experiments.csv and create artifacts registry"

  action: (S) ->
    csv = await S.need 'experiments_csv'
    outputDir = S.param 'output_dir'
    modelId = S.param 'model'

    lines = String(csv).trim().split /\r?\n/
    throw new Error 'Invalid experiments.csv (missing header)' unless lines[0]?.length

    lockHash = crypto.createHash('sha1').update(String(csv), 'utf8').digest('hex')
    S.saveThis 'lock_hash', lockHash

    registry =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      runs: [
        {
          model_id: modelId
          output_root: outputDir
          adapter_dir: path.join(outputDir, 'adapter')
          fused_dir: path.join(outputDir, 'fused')
          quantized_dir: path.join(outputDir, 'quantized')
        }
      ]

    S.make 'artifacts_registry', registry
    S.done()
    return
