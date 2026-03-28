readCSVText = (text) ->
  lines = String(text).split(/\r?\n/).filter (l) -> l.trim().length
  return [] unless lines.length
  headers = lines[0].split(',').map (h) -> h.trim()
  rows = []
  for line in lines.slice(1)
    cols = line.split(',').map (c) -> c.trim()
    row = {}
    for i in [0...headers.length]
      row[headers[i]] = cols[i] ? ''
    row.iters = parseInt(row.iters ? 0)
    row.batch_size = parseInt(row.batch_size ? 0)
    row.max_seq_length = parseInt(row.max_seq_length ? 0)
    row.learning_rate = parseFloat(row.learning_rate ? 0)
    rows.push row
  rows

selectRows = (rows, onlyModelId, onlyRow) ->
  if onlyRow? and String(onlyRow) isnt 'None' and String(onlyRow).length
    idx = parseInt onlyRow
    return if rows[idx]? then [rows[idx]] else []
  if onlyModelId? and String(onlyModelId).length
    return rows.filter (r) -> r.model_id is onlyModelId
  rows

@step =
  desc: "Run MLX LoRA trainings based on experiments.csv"

  action: (S) ->
    csv = await S.need 'experiments_csv'

    dryRun = !!S.param 'dry_run'
    onlyModelId = S.param 'only_model_id'
    onlyRow = S.param 'only_row'

    rows = readCSVText csv
    todo = selectRows rows, onlyModelId, onlyRow

    lastStdout = ''
    lastRow = null

    for row in todo
      args =
        model: row.model_id
        data: row.data_dir
        train: null
        "adapter-path": row.adapter_path
        "batch-size": String(row.batch_size)
        iters: String(row.iters)
        "max-seq-length": String(row.max_seq_length)
        "learning-rate": String(row.learning_rate)

      if dryRun
        console.log '[train] dry run', JSON.stringify(args)
        lastStdout = ''
      else
        lastStdout = S.callMLX 'lora', args
      lastRow = row

    S.saveThis 'train:last_row', lastRow
    S.make 'lora_stdout', lastStdout
    S.done()
    return
