let conns = Mvalue.create (ref [])

let sock_listener =
  let port = int_of_string Sys.argv.(1) in
  let max_pending_connections = 8 in
  let descr = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt descr Unix.SO_REUSEADDR true;
  Unix.setsockopt descr Unix.SO_REUSEPORT true;
  Unix.bind descr (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen descr max_pending_connections;
  Printf.printf "Listening on port %d\n%!" port;
  descr

let () =
  while true do
    let sock, addr = Unix.accept sock_listener in
    match addr with
    | Unix.ADDR_INET (inet_addr, port) ->
        Printf.printf "New connection: %s:%d\n%!"
          (Unix.string_of_inet_addr inet_addr)
          port;
        let _ =
          Domain.spawn (fun () -> Conn.handle { name = None; sock } conns)
        in
        ()
    | _ -> ()
  done
