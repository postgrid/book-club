type t = { name : string; sock : Unix.file_descr; bs : Bufstream.t }

let delim = '|'
let name_timeout = 3.0
let all_conns = Mvalue.create (ref [])

let rec read_until_delim sock bs =
  let b = Bufstream.read_bytes_until_char bs '|' in
  match b with
  | Some b ->
      (* Skip the delimiter *)
      Bufstream.consume_bytes bs 1;
      b
  | _ ->
      let recv_buf = Bytes.create 256 in
      let count = Unix.recv sock recv_buf 0 256 [] in
      Bufstream.write_subbytes bs recv_buf 0 count;
      read_until_delim sock bs

let read_string_until_delim sock bs =
  Bytes.unsafe_to_string @@ read_until_delim sock bs

let handle sock =
  let name_to_remove = ref None in
  try
    let bs = Bufstream.create 16 in
    (* Set a recv timeout until we get to the loop, otherwise rando connections who don't
       know the protocol might hog resources *)
    Unix.setsockopt_float sock Unix.SO_RCVTIMEO name_timeout;
    let name = read_string_until_delim sock bs in
    (* If there's another conn with the same name, then kill this conn.
       Otherwise, add it. *)
    Mvalue.protect all_conns (fun conns ->
        let has_same_name_conn =
          List.exists (fun oc -> oc.name = name) !conns
        in
        if has_same_name_conn then (
          name_to_remove := Some (name ^ " (copy, so I'm killing it)");
          raise Exit)
        else conns := { name; sock; bs } :: !conns);
    name_to_remove := Some name;
    Printf.printf "Connection named itself '%s'\n%!" name;
    (* Time out in 30s now that we've established a name *)
    Unix.setsockopt_float sock Unix.SO_RCVTIMEO 30.0;
    while true do
      let dest_name = read_string_until_delim sock bs in
      let packet_len_str = read_string_until_delim sock bs in
      let packet_len = int_of_string packet_len_str in
      let () =
        if packet_len < 0 then raise (Invalid_argument "Negative packet length")
      in
      (* We may have already buffered some of the input so read the _remaining_ amount *)
      let packet_buf =
        Sockutil.read_all sock (packet_len - Bufstream.length bs)
      in
      Bufstream.write_bytes bs packet_buf;
      let other_conn =
        Mvalue.protect all_conns (fun conns ->
            List.find_opt (fun oc -> oc.name = dest_name) !conns)
      in
      (* If there's no other socket with that name, then
         this message just goes into the aether *)
      match other_conn with
      (* Can't send to yourself hence the when *)
      | Some oc when oc.name != name ->
          (* Prefix the message with the sender and the packet length *)
          Sockutil.write_all oc.sock
            (Bytes.unsafe_of_string @@ Printf.sprintf "%s|%d|" name packet_len);
          Sockutil.write_all oc.sock (Bufstream.read_bytes bs packet_len)
      | _ -> Bufstream.consume_bytes bs packet_len
    done
  with e ->
    let exc_s = Printexc.to_string e in
    let exc_b = Printexc.get_backtrace () in
    let rem_name = Option.value !name_to_remove ~default:"(unnamed)" in
    Printf.printf "Connection '%s' raised an exception: %s %s\n%!" rem_name
      exc_s exc_b;
    Mvalue.protect all_conns (fun conns ->
        conns := List.filter (fun oc -> oc.name = rem_name) !conns);
    Unix.close sock
