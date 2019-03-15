open Bos
open Rresult

let new_tap br =
  let rec free_tap n =
    let tap_name = "tap" ^ string_of_int n in
    match Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "addr" % "show" % "dev" % tap_name) with
    | Error _ -> tap_name
    | Ok _ -> free_tap (succ n)
  in
  let tap = free_tap 0 in
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "tuntap" % "add" % tap % "mode" % "tap") >>= fun () ->
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "link" % "set" % tap % "master" % br) >>= fun () ->
  Ok tap

(*
let spawn kernel =
  let tap = new_tap "br0" in
  Bos.OS.Cmd.run Bos.Cmd.()
*)

(* Things we need to do:
 * - Create new tap
 * - Spawn unikernel and attach the network tap
 * - Stop unikernel
 * - Destroy tap device
*)

let () = ()
