type t = { mutable name : string option; sock : Unix.file_descr }

let read_all sock n =
  let buf = Bytes.create n in
  let bytes_read = ref 0 in
  while !bytes_read < n do
    let count = Unix.recv sock buf !bytes_read (n - !bytes_read) [] in
    if count = 0 then raise End_of_file else bytes_read := !bytes_read + count
  done;
  buf

let read_bool sock =
  let buf = read_all sock 1 in
  Bytes.get buf 0 <> char_of_int 0

let read_int32_le sock =
  let buf = read_all sock 4 in
  Int32.to_int (Bytes.get_int32_le buf 0)

let read_string sock =
  let len = read_int32_le sock in
  Bytes.to_string (read_all sock len)

let write_all sock buf =
  let bytes_written = ref 0 in
  let len = Bytes.length buf in
  while !bytes_written < len do
    let count = Unix.send sock buf !bytes_written (len - !bytes_written) [] in
    if count = 0 then raise End_of_file
    else bytes_written := !bytes_written + count
  done

let handle conn all_conns =
  try
    let name = read_string conn.sock in
    conn.name <- Some name;
    (* If there's another conn with the same name, then kill this conn.
       Otherwise, add it. *)
    Mvalue.protect all_conns (fun conns ->
        let has_same_name_conn =
          List.exists (fun oc -> oc.name = conn.name) !conns
        in
        if has_same_name_conn then (
          conn.name <- Some (Option.get conn.name ^ " (copy)");
          raise Exit)
        else conns := conn :: !conns);
    Printf.printf "Connection named itself '%s'\n%!" name;
    while true do
      let dest_name = read_string conn.sock in
      let packet_len = read_int32_le conn.sock in
      let buf = read_all conn.sock packet_len in
      let other_conn =
        Mvalue.protect all_conns (fun conns ->
            List.find_opt (fun oc -> oc.name = Some dest_name) !conns)
      in
      (* If there's no other socket with that name, then
         this message just goes into the aether *)
      match other_conn with
      (* Can't send to yourself hence the when *)
      | Some oc when oc.name != conn.name -> write_all oc.sock buf
      | _ -> ()
    done
  with _ ->
    Printf.printf "Connection '%s' died\n%!"
      (Option.value conn.name ~default:"(unnamed)");
    Mvalue.protect all_conns (fun conns ->
        conns := List.filter (fun oc -> oc.name = conn.name) !conns);
    Unix.close conn.sock
