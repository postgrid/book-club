let _example_run =
  {|
CONSTRAINT_INT_GTE x 15

BEGIN_TX
SET_TX 1 x 10
COMMIT_TX 1

GET x

BEGIN_TX
BEGIN_TX

SET_TX 3 x a

COMMIT_TX 3

GET_TX 2 x

ROLLBACK_TX 2
|}

let _conflict_run =
  {|
# Comment lines start with '#'

# Begin a transaction, should output transaction ID (monotonically increasing values): 1
BEGIN_TX

# SET_TX (transaction ID) (key) (value, must be numeric)
# Outputs the previous value of x at the time when this transaction was created: ()
SET_TX 1 x 10

# GET_TX (transaction ID) (key) outputs either the number at the key (in this transaction) or () if none 
GET_TX 1 x

# Output: 10
SET_TX 1 x 11

# Output: 11
GET_TX 1 x

# GET (key) tries to get the value at 'key' outside of a transaction, in this case () since
# 'x' has not been set.
GET x

# COMMIT_TX (transaction ID) commits the transaction with the given ID, making its changes visible to all future requests
# Output: ()
COMMIT_TX 1

# Output: 2
BEGIN_TX
# Output: 3
BEGIN_TX

# Output: 11
GET_TX 2 x

# Output: 11
SET_TX 2 x 12

# Output: 11
# Since it should not be able to see the modifications made by TX 2
GET_TX 3 x

# Output: 11
SET_TX 3 x 13

# Output: ()
ROLLBACK_TX 2

# Output: ()
COMMIT_TX 3

# Output: 13
GET x

# Output: 4
BEGIN_TX
# Output: 5
BEGIN_TX

# Sets x to 14 within transaction 4
# Outputs previous value: 13
SET_TX 4 x 14

COMMIT_TX 4

# Output: 13
GET_TX 5 x
# Output: 13
SET_TX 5 x 15

# Output: (CONFLICT)
COMMIT_TX 5
|}

let () =
  Printexc.record_backtrace true;
  let db = Db.create 16 in
  let cmds =
    Cmd_reader.read_all_skip_invalid (String.split_on_char '\n' _example_run)
  in
  let res = Cmd_runner.exec_all db cmds in
  assert (List.length db.txs = 0);
  List.iter print_endline res
