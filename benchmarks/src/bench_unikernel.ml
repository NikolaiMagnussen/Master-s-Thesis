open Lwt.Infix

let get_data () =
  let uri = Uri.of_string "http://10.0.0.2:8000" in
  let rec req uri = 
    let submit_req () = Cohttp_lwt_unix.Client.get uri in
    let handle_succ (resp, _body) =
      let s = Cohttp_lwt_unix.Response.status resp |> Cohttp.Code.string_of_status in
      Logs_lwt.info (fun m -> m "Success with status %s" s) >>= fun () ->
      Lwt.return_unit in
    let handle_fail e = 
      Logs_lwt.warn (fun m -> m "Failed %s" (Printexc.to_string e)) >>= fun () ->
      req uri in
    Lwt.try_bind submit_req handle_succ handle_fail in
  req uri

let connect () =
  let ip = Unix.inet_addr_of_string "10.0.0.2" in
  let addr = Unix.ADDR_INET (ip, 8000) in
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let rec con n =
    Logs.info (fun m -> m "Connecting - try %d" n);
    try Unix.connect socket addr; 
      Unix.close socket
    with _ -> con (succ n)
  in
  con 0

let start tap devnull =
  let hvt = "./solo5-hvt" in
  let path = "./static.hvt" in
  Logs.info (fun m -> m "Starting process..");
  let pid = Unix.create_process hvt [|hvt; "--net="^tap; path; "--ipv4=10.0.0.2/24"|] devnull devnull devnull in
  Logs.info (fun m -> m "Started process with pid %d" pid);
  connect ();
  pid

let start_lwt tap devnull =
  let hvt = "./solo5-hvt" in
  let path = "./static.hvt" in
  let pid = Unix.create_process hvt [|hvt; "--net="^tap; path; "--ipv4=10.0.0.2/24"|] devnull devnull devnull in
  get_data () >>= fun () ->
  Lwt.return pid

let stop pid =
  Unix.kill pid Sys.sigterm;
  Unix.waitpid [] pid

let time f n d =
  let start = Mtime_clock.now() in
  let res = f n d in
  let stop = Mtime_clock.now() in
  let diff = Mtime.span start stop in
  (diff, res)

let time_lwt f n d =
  let start = Mtime_clock.now() in
  f n d >>= fun res ->
  let stop = Mtime_clock.now() in
  let diff = Mtime.span start stop in
  Lwt.return (diff, res)

let rec bench_lwt l n devnull =
  if n <= 0 then
    Lwt.return l
  else 
    time_lwt start_lwt "tap0" devnull >>= fun (diff, pid) ->
    let _ = stop pid in
    bench_lwt (diff :: l) (n-1) devnull

let rec bench l n devnull =
  if n <= 0 then
    l
  else 
    let (diff, pid) = time start "tap0" devnull in
    let _ = stop pid in
    bench (diff :: l) (n-1) devnull

let main_lwt num_times =
  let devnull = Unix.openfile "/dev/null" [Unix.O_RDWR] 0o700 in
  bench_lwt [] num_times devnull >>= fun l ->
  Unix.close devnull;
  let times = List.map Mtime.Span.to_us l |> Array.of_list in
  let mean = Owl_base_stats.mean times in
  let std = Owl_base_stats.std ~mean times in
  Printf.printf "BENCH UNIKERNEL %d runs:\n\tMean = %fus\n\tStd  = %fus\n" num_times mean std;
  Lwt.return_unit

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
  (*Lwt_main.run @@ main_lwt num_times*)
  main num_times
