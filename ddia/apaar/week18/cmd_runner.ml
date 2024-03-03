let conv_opt opt_s = match opt_s with Some v -> v | None -> "()"

let exec_one db cmd =
  let res =
    match cmd with
    | Cmd.BeginTx ->
        let tx = Db.start_tx db in
        string_of_int tx.tid
    | Cmd.GetTx { tid; key } ->
        let tx = Db.find_tx db tid in
        let value = Db.get_tx db tx key in
        conv_opt value
    | Cmd.SetTx { tid; key; value } ->
        let tx = Db.find_tx db tid in
        let prev_value = Db.set_tx db tx key value in
        conv_opt prev_value
    | Cmd.CommitTx { tid } -> (
        let tx = Db.find_tx db tid in
        try
          Db.commit_tx db tx;
          "()"
        with Db.Conflict s -> Printf.sprintf "(CONFLICT %s)" s)
    | Cmd.RollbackTx { tid } ->
        let tx = Db.find_tx db tid in
        Db.rollback_tx db tx;
        "()"
    | Cmd.Get { key } -> Db.get db key |> conv_opt
    | Cmd.Set { key; value } -> Db.set db key value |> conv_opt
  in
  Printf.sprintf "%s = %s" (Cmd.to_string cmd) res

let exec_all db cmds =
  let rec loop acc cmds =
    match cmds with
    | cmd :: cmds ->
        let res = exec_one db cmd in
        loop (res :: acc) cmds
    | _ -> acc
  in
  loop [] cmds |> List.rev
