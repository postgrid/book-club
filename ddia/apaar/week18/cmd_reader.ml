let read_one line =
  let parts = String.split_on_char ' ' line |> Array.of_list in
  match parts.(0) with
  | "BEGIN_TX" -> Some Cmd.BeginTx
  | "GET_TX" ->
      Some (Cmd.GetTx { tid = int_of_string parts.(1); key = parts.(2) })
  | "SET_TX" ->
      Some
        (Cmd.SetTx
           { tid = int_of_string parts.(1); key = parts.(2); value = parts.(3) })
  | "COMMIT_TX" -> Some (Cmd.CommitTx { tid = int_of_string parts.(1) })
  | "ROLLBACK_TX" -> Some (Cmd.RollbackTx { tid = int_of_string parts.(1) })
  | "GET" -> Some (Cmd.Get { key = parts.(1) })
  | "SET" -> Some (Cmd.Set { key = parts.(1); value = parts.(2) })
  | "CONSTRAINT_IS_INT" -> Some (Cmd.ConstraintIsInt { key = parts.(1) })
  | "CONSTRAINT_INT_GTE" ->
      Some
        (Cmd.ConstraintIntGte
           { key = parts.(1); value = int_of_string parts.(2) })
  | "CONSTRAINT_INT_LTE" ->
      Some
        (Cmd.ConstraintIntLte
           { key = parts.(1); value = int_of_string parts.(2) })
  | _ -> None

let read_all_skip_invalid lines =
  let rec loop acc lines =
    match lines with
    | line :: lines -> (
        let cmd = read_one line in
        match cmd with
        | Some cmd -> loop (cmd :: acc) lines
        | None -> loop acc lines)
    | _ -> acc
  in
  loop [] lines |> List.rev
