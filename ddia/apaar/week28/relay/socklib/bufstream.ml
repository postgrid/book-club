type t = { buf : Buffer.t; mutable read_pos : int }

let create len = { buf = Buffer.create len; read_pos = 0 }
let write_bytes t b = Buffer.add_bytes t.buf b
let write_subbytes t b ofs len = Buffer.add_subbytes t.buf b ofs len
let length t = Buffer.length t.buf - t.read_pos

let clear t =
  Buffer.clear t.buf;
  t.read_pos <- 0

let unsafe_consume_bytes t len =
  t.read_pos <- t.read_pos + len;
  if t.read_pos = Buffer.length t.buf then clear t

let consume_bytes t len =
  if t.read_pos + len > Buffer.length t.buf then
    raise (Invalid_argument "Skipped bytes exceed buffer length")
  else unsafe_consume_bytes t len

let read_bytes t len =
  let b = Bytes.unsafe_of_string @@ Buffer.sub t.buf t.read_pos len in
  consume_bytes t len;
  b

let read_remaining t = read_bytes t (Buffer.length t.buf - t.read_pos)

let read_bytes_until_char t ch =
  let b =
    Bytes.unsafe_of_string @@ Buffer.sub t.buf t.read_pos (Buffer.length t.buf)
  in
  let pos = Bytes.index_opt b ch in
  match pos with
  | Some pos ->
      let res = Some (Bytes.sub b 0 pos) in
      consume_bytes t pos;
      res
  | _ -> None
