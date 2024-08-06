type mode =
  | (* Forwards any packets sent to this device to a locally reachable HTTP server.

       It makes a new connection to the server for every packet it receives. This
       assumes you have an tunnel HttpClient on the other end that's faithfully
       setting packet_len to the length of the HTTP message before sending it
       over to the relay.

       Once it has sent the request, it waits for a response from your local server
       and then forwards it to the relay server. It parses some of the HTTP in order
       to determine the packet length.

       Note that since this only has one connection open to the relay server, it can
       only service one request at at time even if there are mulitple different clients.

       TODO(Apaar): Maybe we can mitigate that by letting multiple devices register under
       the same name and round-robin across them? *)
    HttpServer

type t = {
  mode : mode;
  relay_addr : Unix.sockaddr;
  relay_device_name : string;
  local_addr : Unix.sockaddr;
}

let usage_msg =
  "relay-tunnel -local localhost:8080 -relay localhost:2892 -devname mydevice \
   -mode http_server"

let get_inet_addr host port =
  let open Unix in
  match getaddrinfo host port [] with
  | { ai_addr = ADDR_INET _ as sa; _ } :: _ -> sa
  | _ ->
      failwith
      @@ Printf.sprintf "%s:%s did not resolve to a valid ADDR_INET" host port

let addr_of_string hp =
  match String.split_on_char ':' hp with
  | [ host; port ] -> get_inet_addr host port
  | _ -> failwith @@ Printf.sprintf "Invalid host + port string: %s" hp

let parse_argv args =
  let relay = ref None in
  let devname = ref None in
  let local = ref None in
  let speclist =
    [
      ( "-relay",
        Arg.String (fun s -> relay := Some s),
        "Host + port combo for the relay server (e.g. localhost:2892)" );
      ( "-devname",
        Arg.String (fun s -> devname := Some s),
        "Device name on the relay server (e.g. mydevice)" );
      ( "-local",
        Arg.String (fun s -> local := Some s),
        "Host + port combo for the local server to forward to (e.g. \
         localhost:8080)" );
      (* TODO(Apaar): Handle mode *)
    ]
  in
  Arg.parse_argv args speclist (fun _ -> ()) usage_msg;
  match (!relay, !devname, !local) with
  | Some relay, Some devname, Some local ->
      {
        mode = HttpServer;
        relay_addr = addr_of_string relay;
        relay_device_name = devname;
        local_addr = addr_of_string local;
      }
  | _ -> failwith "All of -local, -devname, and -relay must be provided"

let parse () = parse_argv Sys.argv
