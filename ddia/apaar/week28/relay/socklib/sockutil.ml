let read_all sock n =
  let buf = Bytes.create n in
  let bytes_read = ref 0 in
  while !bytes_read < n do
    let count = Unix.recv sock buf !bytes_read (n - !bytes_read) [] in
    if count = 0 then raise End_of_file else bytes_read := !bytes_read + count
  done;
  buf

let write_all sock buf =
  let bytes_written = ref 0 in
  let len = Bytes.length buf in
  while !bytes_written < len do
    let count = Unix.send sock buf !bytes_written (len - !bytes_written) [] in
    if count = 0 then raise End_of_file
    else bytes_written := !bytes_written + count
  done
