open Socklib

(* We wrap the socket in a mutex because we want the writes to not be split *)
type t = { name : string; write_sock : Unix.file_descr Mvalue.t }

let delim = '|'
let name_timeout = 3.0
let all_conns = Mvalue.create (ref [])

let read_string_until_delim bfs =
  Bytes.unsafe_to_string @@ Bufsock.read_until_delim_skip_delim bfs delim

let handle sock =
  Printexc.record_backtrace true;
  let name_to_remove = ref None in
  try
    let bfs = Bufsock.create sock 16 in
    (* Set a recv timeout until we get to the loop, otherwise rando connections who don't
       know the protocol might hog resources *)
    Unix.setsockopt_float sock Unix.SO_RCVTIMEO name_timeout;
    let name = read_string_until_delim bfs in
    (* If there's another conn with the same name, then kill this conn.
       Otherwise, add it. *)
    Mvalue.protect all_conns (fun conns ->
        let has_same_name_conn =
          List.exists (fun oc -> oc.name = name) !conns
        in
        if has_same_name_conn then (
          name_to_remove := Some (name ^ " (copy, so I'm killing it)");
          raise Exit
          (* We only store the socket for writing because reads only happen on this thread *))
        else conns := { name; write_sock = Mvalue.create bfs.sock } :: !conns);
    name_to_remove := Some name;
    Printf.printf "Connection named itself '%s'\n%!" name;
    (* Time out in 30s now that we've established a name *)
    Unix.setsockopt_float sock Unix.SO_RCVTIMEO 30.0;
    Unix.setsockopt_float sock Unix.SO_SNDTIMEO 30.0;
    while true do
      let dest_name = read_string_until_delim bfs in
      let packet_len = int_of_string @@ read_string_until_delim bfs in
      let () = if packet_len < 0 then invalid_arg "Negative packet length" in
      let packet = Bufsock.read_bytes bfs packet_len in
      let other_conn =
        Mvalue.protect all_conns (fun conns ->
            List.find_opt (fun oc -> oc.name = dest_name) !conns)
      in
      (* If there's no other socket with that name, then
         this message just goes into the aether *)
      match other_conn with
      (* Can't send to yourself hence the when *)
      | Some oc when oc.name != name ->
          Mvalue.protect oc.write_sock (fun sock ->
              (* Prefix the message with the sender and the packet length *)
              Sockutil.write_all sock
                (Bytes.unsafe_of_string
                @@ Printf.sprintf "%s|%d|" name packet_len);
              Sockutil.write_all sock packet)
      | _ -> ()
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
