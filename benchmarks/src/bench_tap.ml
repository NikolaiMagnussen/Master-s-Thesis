open Rresult

let new_tap br =
  let rec free_tap n =
    let tap_name = "tap" ^ string_of_int n in
    match Bos.OS.Cmd.run_status ~quiet:true Bos.Cmd.(v "ip" % "addr" % "show" % "dev" % tap_name) with
    | Ok `Exited 0 -> free_tap (succ n)
    | _ -> tap_name
  in
  let tap = free_tap 0 in
  Bos.OS.Cmd.run_status ~quiet:true Bos.Cmd.(v "ip" % "tuntap" % "add" % tap % "mode" % "tap") >>= fun _ ->
  Bos.OS.Cmd.run_status ~quiet:true Bos.Cmd.(v "ip" % "link" % "set" % tap % "master" % br) >>= fun _ ->
  Bos.OS.Cmd.run_status ~quiet:true Bos.Cmd.(v "ip" % "link" % "set" % "dev" % tap % "up") >>= fun _ ->
  Ok tap

let del_tap tap =
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "tuntap" % "del" % "dev" % tap % "mode" % "tap")

let time f n =
  let start = Mtime_clock.now() in
  let res = f n in
  let stop = Mtime_clock.now() in
  let diff = Mtime.span start stop in
  (diff, res)

let rec bench l n =
  if n <= 0 then
    Ok l
  else
    let (diff, tap) = time new_tap "br0" in
    match tap with
    | Ok tap -> del_tap tap >>= fun () -> bench (diff :: l) (n-1)
    | Error e -> Error e

let () = 
  let num_times = Sys.argv.(1) |> int_of_string in
  match bench [] num_times with
  | Error `Msg m -> Printf.printf "Something went wrong: %s\n" m
  | Ok l -> let times = List.map Mtime.Span.to_us l |> Array.of_list in
    let mean = Owl_base_stats.mean times in
    let std = Owl_base_stats.std ~mean times in
    Printf.printf "BENCH TAP %d runs:\n\tMean = %fus\n\tStd  = %fus\n" num_times mean std
