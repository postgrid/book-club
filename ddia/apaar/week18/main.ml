let example_run =
  {|
BEGIN_TX
SET_TX 1 x 10
COMMIT_TX 1

GET x

BEGIN_TX
BEGIN_TX

SET_TX 3 x 30

COMMIT_TX 3

GET_TX 2 x

ROLLBACK_TX 2
|}

let () =
  Printexc.record_backtrace true;
  let db = Db.create 16 in
  let cmds =
    Cmd_reader.read_all_skip_invalid (String.split_on_char '\n' example_run)
  in
  let res = Cmd_runner.exec_all db cmds in
  List.iter print_endline res
