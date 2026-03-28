crypto = require 'crypto'
child = require 'child_process'
rand = require 'seedrandom'

@step =
  desc: "Fetch and preprocess a HuggingFace dataset into train and valid artifacts"

  action: (S) ->
    dataDir = S.param 'data_dir'
    hfDataset = S.param 'hf_dataset'
    subset = S.param 'subset'
    mode = S.param 'mode'
    validFract = parseFloat S.param 'valid_fract'
    minWords = parseInt S.param 'min_words'
    maxWords = parseInt S.param 'max_words'
    seed = S.param 'seed'

    rng = rand seed
    wc = (s) -> String(s).trim().split(/\s+/).length
    sha = (s) -> crypto.createHash('sha256').update(String(s)).digest('hex')

    pyScript = """
from datasets import load_dataset
import json
ds = load_dataset(#{JSON.stringify(hfDataset)}, name=#{JSON.stringify(subset)}, split='train')
for r in ds:
  print(json.dumps(r))
"""

    res = child.spawnSync 'python', ['-u', '-c', pyScript], encoding: 'utf8'
    if res.error? or res.status isnt 0
      console.error res.stderr
      throw new Error 'datasets.load_dataset failed'

    rows = []
    for line in String(res.stdout ? '').split(/\r?\n/)
      continue unless line.trim()
      try
        row = JSON.parse line
      catch
        continue
      quote = String(row.quote ? '').trim()
      author = String(row.author ? '').trim()
      continue unless quote.length
      text = if mode is 'plain'
        quote
      else
        instr = if author then "Write a short motivational quote in the style of #{author}." else 'Write a short motivational quote.'
        "Instruction:\n#{instr}\n\nResponse:\n#{quote}"
      continue unless minWords <= wc(text) <= maxWords
      rows.push text

    seen = new Set()
    uniq = []
    for text in rows
      h = sha text
      continue if seen.has h
      seen.add h
      uniq.push text

    uniq.sort -> rng() - 0.5
    validN = Math.max 1, Math.floor(uniq.length * validFract)
    valid = uniq.slice 0, validN
    train = uniq.slice validN

    trainRows = train.map (text) -> { text }
    validRows = valid.map (text) -> { text }

    contract =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      data_dir: dataDir
      filenames:
        train:
          chosen: 'train.jsonl'
          resolved: "#{dataDir}/train.jsonl"
        valid:
          chosen: 'valid.jsonl'
          resolved: "#{dataDir}/valid.jsonl"
      schema:
        format: 'jsonl'
        fields:
          text: 'string'

    catalogEntry = (label, arr) ->
      lines = arr.length
      acc = crypto.createHash 'sha256'
      bytes = 0
      for row in arr
        payload = JSON.stringify(row) + "\n"
        bytes += Buffer.byteLength payload
        acc.update payload
      sum = acc.digest 'hex'
      {
        path: "#{dataDir}/#{label}.jsonl"
        lines: lines
        bytes: bytes
        sha256: sum
        stats:
          num_valid_examples: lines
          num_bytes: bytes
          sha256: sum
      }

    catalog =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      entries:
        train: catalogEntry 'train', trainRows
        valid: catalogEntry 'valid', validRows

    S.make 'train_rows', trainRows
    S.make 'valid_rows', validRows
    S.make 'data_contract', contract
    S.make 'data_catalog', catalog
    S.done()
    return
