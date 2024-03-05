type t =
  | BeginTx
  | GetTx of { tid : int; key : string }
  | SetTx of { tid : int; key : string; value : string }
  | CommitTx of { tid : int }
  | RollbackTx of { tid : int }
  | Get of { key : string }
  | Set of { key : string; value : string }
  | ConstraintIsInt of { key : string }
  | ConstraintIntGte of { key : string; value : int }
  | ConstraintIntLte of { key : string; value : int }

let to_string t =
  match t with
  | BeginTx -> "BEGIN_TX"
  | GetTx { tid; key } -> Printf.sprintf "GET_TX %d %s" tid key
  | SetTx { tid; key; value } -> Printf.sprintf "SET_TX %d %s %s" tid key value
  | CommitTx { tid } -> Printf.sprintf "COMMIT_TX %d" tid
  | RollbackTx { tid } -> Printf.sprintf "ROLLBACK_TX %d" tid
  | Get { key } -> Printf.sprintf "GET %s" key
  | Set { key; value } -> Printf.sprintf "SET %s %s" key value
  | ConstraintIsInt { key } -> Printf.sprintf "CONSTRAINT_IS_INT %s" key
  | ConstraintIntGte { key; value } -> Printf.sprintf "CONSTRAINT_INT_GTE %s %d" key value
  | ConstraintIntLte { key; value } -> Printf.sprintf "CONSTRAINT_INT_LTE %s %d" key value
