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
  let _ = Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "tuntap" % "del" % "dev" % tap % "mode" % "tap") in
  ()

let connect ip =
  let ip = Unix.inet_addr_of_string ip in
  let addr = Unix.ADDR_INET (ip, 8000) in
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let rec con n =
    Logs.debug (fun m -> m "Connecting - try %d" n);
    try Unix.connect socket addr; 
      Unix.close socket
    with _ -> con (succ n)
  in
  con 0

let start tap devnull n =
  let ip = "10.0.0." ^ string_of_int (n+2) in
  let hvt = "./solo5-hvt" in
  let path = "./static.hvt" in
  Logs.debug (fun m -> m "Starting process..");
  let pid = Unix.create_process hvt [|hvt; "--mem=32"; "--net="^tap; path; "--ipv4="^ip^"/24"|] devnull devnull devnull in
  Logs.debug (fun m -> m "Started process with pid %d" pid);
  connect ip;
  pid

let stop pid =
  Unix.kill pid Sys.sigterm;
  Unix.waitpid [] pid

let time f n d i =
  let start = Mtime_clock.now () in
  let res = f n d i in
  let stop = Mtime_clock.now () in
  let diff = Mtime.span start stop in
  Logs.debug (fun m -> m "Diff is %f" (Mtime.Span.to_ms diff));
  (diff, res)

let rec bench l n devnull =
  if n <= 0 then
    l
  else 
    match new_tap "br0" with
    | Ok tap ->
      let _ = Logs.debug (fun m -> m "Going to time this now..\n") in
      let (diff, pid) = time start "tap0" devnull n in
      Logs.debug (fun m -> m "Finished timing, going to sleep now...");
      let _ = stop pid in
      del_tap tap;
      Unix.sleep 5;
      bench (diff :: l) (n-1) devnull
    |Error _ -> l

let main num_times =
  let devnull = Unix.openfile "/dev/null" [Unix.O_RDWR] 0o700 in
  let l = bench [] num_times devnull in
  Unix.close devnull;
  let times = List.map Mtime.Span.to_us l |> Array.of_list in
  let mean = Owl_base_stats.mean times in
  let std = Owl_base_stats.std ~mean times in
  Printf.printf "BENCH UNIKERNEL %d runs:\n\tMean = %fus\n\tStd  = %fus\n" num_times mean std

let () = 
  Fmt_tty.setup_std_outputs ();
  Logs.set_level @@ Some Logs.Info;
  Logs.set_reporter @@ Logs_fmt.reporter ();
  let num_times = Sys.argv.(1) |> int_of_string in
  main num_times
