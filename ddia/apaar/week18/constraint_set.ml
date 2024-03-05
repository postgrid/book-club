type c = IsInt | IntGte of int | IntLte of int
type t = c list

let empty = []
let singleton c = [ c ]

exception AmbiguousConstraint
exception InvalidConstraint

let add t c =
  if List.mem c t then t
  else
    let rec loop acc cs =
      match (c, cs) with
      | IntGte _, IntGte _ :: _
      | IntLte _, IntLte _ :: _
      | IsInt, IntGte _ :: _
      | IsInt, IntLte _ :: _ ->
          raise AmbiguousConstraint
      | IntGte a, IntLte b :: _ when b < a -> raise InvalidConstraint
      | IntLte a, IntGte b :: _ when a < b -> raise InvalidConstraint
      | _, c :: cs -> loop (c :: acc) cs
      | _, [] -> acc
    in
    loop [] t

let constraint_to_string c =
  match c with
  | IsInt -> "IS_INT"
  | IntGte a -> Printf.sprintf "INT_GTE %d" a
  | IntLte a -> Printf.sprintf "INT_LTE %d" a

let check_constraint c v =
  match c with
  | IsInt -> Option.is_some (int_of_string_opt v)
  | IntGte a -> (
      let i = int_of_string_opt v in
      match i with Some i -> i >= a | None -> false)
  | IntLte a -> (
      let i = int_of_string_opt v in
      match i with Some i -> i <= a | None -> false)

let rec check cs v =
  match cs with
  | c :: cs -> if not (check_constraint c v) then Some c else check cs v
  | _ -> None

exception ConstraintFailure of c

let check_raise cs v =
  let failing_constraint = check cs v in
  match failing_constraint with
  | Some c -> raise (ConstraintFailure c)
  | _ -> ()
