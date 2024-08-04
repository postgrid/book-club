(* Protects a value with a mutex *)
type 'a t = { mutex : Mutex.t; value : 'a }

let create v = { mutex = Mutex.create (); value = v }
let protect t f = Mutex.protect t.mutex (fun () -> f t.value)
