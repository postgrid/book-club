open Socklib

let args = Cli.parse ()

let relay_sock =
  let sock = Unix.(socket PF_INET SOCK_STREAM 0) in
  Unix.connect sock args.relay_addr;
  (* Send our name over *)
  Sockutil.write_all sock
    (Bytes.unsafe_of_string @@ Printf.sprintf "%s|" args.relay_device_name);
  Bufsock.create sock 64

let read_relay_header () =
  Bytes.unsafe_to_string @@ Bufsock.read_until_delim_skip_delim relay_sock '|'

let http_server_loop () =
  let recv_bytes = Bytes.create 256 in
  let resp_buf = Buffer.create 256 in
  while true do
    let client_devname = read_relay_header () in
    let client_packet_len = int_of_string @@ read_relay_header () in
    let client_packet = Bufsock.read_bytes relay_sock client_packet_len in
    let local_serv_sock = Unix.(socket PF_INET SOCK_STREAM 0) in
    (try
       Unix.connect local_serv_sock args.local_addr;
       Sockutil.write_all local_serv_sock client_packet
     with e ->
       Unix.close local_serv_sock;
       raise e);
    (* Now we buffer the response *)
    let _ =
      Http.buffer_entire_message relay_sock.bs
        (fun () ->
          let count =
            Unix.recv relay_sock.sock recv_bytes 0 (Bytes.length recv_bytes) []
          in
          Bufstream.write_subbytes relay_sock.bs recv_bytes 0 count)
        resp_buf
    in
    Printf.printf "%s|%s\n" client_devname
      (Bytes.to_string @@ Buffer.to_bytes resp_buf);
    Buffer.clear resp_buf
  done

let () = http_server_loop ()
