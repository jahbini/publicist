crypto = require 'crypto'

hashText = (s) ->
  crypto.createHash('sha256').update(String(s), 'utf8').digest('hex')

percentiles = (vals, q = [5, 25, 50, 75, 95]) ->
  return {} unless vals?.length
  arr = vals.slice().sort (a, b) -> a - b
  out = {}
  for p in q
    idx = Math.max 0, Math.min arr.length - 1, Math.round((p / 100) * (arr.length - 1))
    out["p#{p}"] = arr[idx]
  out

scanRows = (rows, field) ->
  eosMarkers = ['</s>', '###', '\n\n', '<|eot_id|>', '<|endoftext|>']
  lengths = []
  hashes = []
  errors =
    missing_field: 0
    non_string_field: 0
  empties =
    empty_exact: 0
    whitespace_only: 0
    leading_whitespace: 0
    trailing_whitespace: 0
  eosHits = {}
  eosHits[m] = 0 for m in eosMarkers
  good = []
  bad = []

  for row in rows
    unless row?[field]?
      errors.missing_field += 1
      bad.push '[missing_field]' if bad.length < 3
      continue
    unless typeof row[field] is 'string'
      errors.non_string_field += 1
      bad.push '[non_string_field]' if bad.length < 3
      continue

    val = row[field]
    empties.empty_exact += 1 if val is ''
    empties.whitespace_only += 1 if val.trim() is ''
    empties.leading_whitespace += 1 if /^\s/.test val
    empties.trailing_whitespace += 1 if /\s$/.test val

    lengths.push val.length
    hashes.push hashText val
    for marker in eosMarkers when val.includes marker
      eosHits[marker] += 1
    good.push val if good.length < 3

  dupCount = 0
  dupExamples = []
  counts = {}
  for h in hashes
    counts[h] ?= 0
    counts[h] += 1
  for h, cnt of counts when cnt > 1
    dupCount += cnt - 1
    dupExamples.push h if dupExamples.length < 3

  ordered = lengths.slice().sort (a, b) -> a - b
  median = if ordered.length then ordered[Math.floor(ordered.length / 2)] else 0

  {
    lines: rows.length
    valid_examples: lengths.length
    errors: errors
    empties: empties
    duplicates:
      duplicate_example_count: dupCount
      sha256_examples: dupExamples
    length_chars:
      count: lengths.length
      min: if lengths.length then Math.min.apply(null, lengths) else 0
      max: if lengths.length then Math.max.apply(null, lengths) else 0
      mean: if lengths.length then lengths.reduce(((a, b) -> a + b), 0) / lengths.length else 0
      median: median
      percentiles: percentiles(lengths)
    eos_markers_hits: eosHits
    samples:
      good_first3: good
      bad_first3: bad
  }

@step =
  desc: "Validate and analyze dataset rows"

  action: (S) ->
    contract  = await S.need 'data_contract'
    trainRows = await S.need 'train_rows'
    validRows = await S.need 'valid_rows'

    textField = 'text'
    if contract?.schema?.fields?
      for k, v of contract.schema.fields
        if String(v).toLowerCase() is 'string'
          textField = k
          break

    report =
      created_utc: new Date().toISOString().replace(/\.\d+Z$/, 'Z')
      text_field: textField
      splits:
        train: scanRows(trainRows ? [], textField)
        valid: scanRows(validRows ? [], textField)

    S.make 'data_report', report
    S.done()
    return
