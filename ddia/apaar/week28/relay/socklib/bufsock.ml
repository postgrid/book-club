type t = { sock : Unix.file_descr; bs : Bufstream.t }

let create sock bs_len = { sock; bs = Bufstream.create bs_len }

let rec read_until_delim t ch =
  let b = Bufstream.read_bytes_until_char t.bs ch in
  match b with
  | Some b -> b
  | _ ->
      let recv_buf = Bytes.create 256 in
      let count = Unix.recv t.sock recv_buf 0 256 [] in
      Bufstream.write_subbytes t.bs recv_buf 0 count;
      read_until_delim t ch

let read_until_delim_skip_delim t ch =
  let b = read_until_delim t ch in
  Bufstream.consume_bytes t.bs 1;
  b

let read_bytes t len =
  let rem_bytes = Sockutil.read_all t.sock (len - Bufstream.length t.bs) in
  Bufstream.write_bytes t.bs rem_bytes;
  Bufstream.read_bytes t.bs len
