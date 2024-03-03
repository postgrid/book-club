module Stringtbl = Hashtbl.Make (String)

type tx = {
  tid : int;
  (* Modifications made by this transaction are stored here *)
  writes : string option Stringtbl.t;
  (* Values in the DB before modifications made by other transactions
     that committed while this Tx was running. Isolates this transaction from
     others without having to clone the entire DB. *)
  reads : string option Stringtbl.t;
}

type t = {
  data : string Stringtbl.t;
  mutable tx_counter : int;
  mutable txs : tx list;
}

let create init_count =
  { data = Stringtbl.create init_count; tx_counter = 1; txs = [] }

let start_tx t =
  let tid = t.tx_counter in
  t.tx_counter <- t.tx_counter + 1;
  let tx = { tid; writes = Stringtbl.create 4; reads = Stringtbl.create 4 } in
  t.txs <- tx :: t.txs;
  tx

let find_tx t tid = List.find (fun tx -> tx.tid = tid) t.txs

let get_tx t tx key =
  match Stringtbl.find_opt tx.writes key with
  | Some v -> v
  | None -> (
      match Stringtbl.find_opt tx.reads key with
      | Some v -> v
      | None -> Stringtbl.find_opt t.data key)

let set_tx t tx key value =
  let prev_value = get_tx t tx key in
  Stringtbl.replace tx.writes key (Some value);
  prev_value

(* Remember the DB value corresponding to `key` if `tx` doesn't
   already recall one or hasn't already modified that key.

   This isolates this transaction from the writes of another tx. *)
let remember_old_value t tx key =
  if Stringtbl.mem tx.writes key || Stringtbl.mem tx.reads key then ()
  else
    let db_value = Stringtbl.find_opt t.data key in
    Stringtbl.replace tx.reads key db_value

exception Conflict of string

let commit_tx t tx =
  let rec loop = function
    | other_tx :: txs ->
        if other_tx.tid = tx.tid then ()
        else
          (* For every write by `tx`, remember the old value in the DB in `other_tx` *)
          Stringtbl.iter
            (fun key _ -> remember_old_value t other_tx key)
            tx.writes;
        loop txs
    | _ -> ()
  in
  loop t.txs;

  (* Check if any of the values we are writing to were changed by another transaction
     in between the time when we started and now. We can detect this by checking if
     a key in tx.writes is present in tx.reads. If it is, then we check whether the
     value in the database is still the same as what it is in tx.reads (meaning that
     the assumptions about the relevant state still hold going into this). If it isn't,
     then there's a conflict. *)
  Stringtbl.iter
    (fun key value ->
      let read_v = Stringtbl.find_opt tx.reads key in
      if Option.is_none read_v then ()
      else
        let db_v = Stringtbl.find_opt t.data key in
        (* If the exact same value we're gonna write is already present in the DB,
           there's really no conflict *)
        if db_v = value then ()
          (* If the value in the database doesn't match what it was at the start of tx,
             then there's a conflict. *)
        else if db_v <> Option.get read_v then raise (Conflict key))
    tx.writes;

  (* Update the database now that we've updated the other transactions that may care *)
  Stringtbl.iter
    (fun key value ->
      match value with
      | Some v -> Stringtbl.replace t.data key v
      | None -> Stringtbl.remove t.data key)
    tx.writes;
  (* Remove the transaction from the list of transactions *)
  t.txs <- List.filter (fun other_tx -> other_tx.tid <> tx.tid) t.txs

let rollback_tx t tx =
  (* This is basically doing nothing but discarding the transaction *)
  t.txs <- List.filter (fun other_tx -> other_tx.tid <> tx.tid) t.txs

let get t key = Stringtbl.find_opt t.data key

let set t key value =
  let tx = start_tx t in
  let prev_value = set_tx t tx key value in
  commit_tx t tx;
  prev_value
