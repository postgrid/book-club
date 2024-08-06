open Socklib

(* This module recongizes HTTP enough to buffer requests
   and responses in memory and send them to our relay
   server. We can't do this without parsing some of HTTP
   since there's no other way to determine the amount of
   data we need to send. *)

type message_info = { host : string option; content_length : int }

(* Returns the HTTP message in a single Buffer object.
   Doesn't interact directly with a unix socket, but instead
   lets you pass in a `recv_into_bs` function yourself.
   Writes everything into `msg_buf` *)
let buffer_entire_message bs recv_into_bs msg_buf =
  let content_length = ref 0 in
  let chunked_encoding = ref false in
  let host = ref None in
  let buffer_body () =
    if !chunked_encoding then
      raise (Invalid_argument "TODO: Handle chunked encoding");
    let init_content_length = !content_length in
    while !content_length > 0 do
      let b = Bufstream.read_remaining bs in
      if Bytes.length b = 0 then recv_into_bs ()
      else (
        Buffer.add_bytes msg_buf b;
        content_length := !content_length - Bytes.length b)
    done;
    { host = !host; content_length = init_content_length }
  in
  let rec buffer_headers () =
    (* Buffer headers line by line , keeping track of any
       Content-Length header we see *)
    let line_bytes = Bufstream.read_bytes_until_char bs '\n' in
    match line_bytes with
    | Some line_bytes ->
        let line = Bytes.unsafe_to_string line_bytes in
        let line = String.trim line in
        if line = "" then (
          Buffer.add_string msg_buf "\r\n";
          buffer_body ())
        else
          let parts = String.split_on_char ':' line in
          (match parts with
          | [ "Content-Length"; len_part ] ->
              content_length := int_of_string (String.trim len_part)
          | [ "Transfer-Encoding"; enc_part ] ->
              chunked_encoding := String.trim enc_part = "Chunked"
          | [ "Host"; host_part ] -> host := Some (String.trim host_part)
          | _ -> ());
          Buffer.add_bytes msg_buf line_bytes;
          Buffer.add_string msg_buf "\r\n";
          buffer_headers ()
    | _ ->
        recv_into_bs ();
        buffer_headers ()
  in
  buffer_headers ()
