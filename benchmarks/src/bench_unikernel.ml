let connect () =
  let ip = Unix.inet_addr_of_string "10.0.0.2" in
  let addr = Unix.ADDR_INET (ip, 8000) in
  let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let rec con () =
    try Unix.connect socket addr; 
      Unix.shutdown socket Unix.SHUTDOWN_SEND
    with _ -> con ()
  in
  con ()

let start tap =
  let hvt = "./solo5-hvt" in
  let path = "./static.hvt" in
  let pid = Unix.create_process hvt [|hvt; "--net="^tap; path; "--ipv4=10.0.0.2/24"|] Unix.stdin Unix.stdout Unix.stderr in
  connect ();
  pid

let stop pid =
  Unix.kill pid Sys.sigterm;
  Unix.waitpid [] pid

let time f n =
  let start = Mtime_clock.now() in
  let res = f n in
  let stop = Mtime_clock.now() in
  let diff = Mtime.span start stop in
  (diff, res)

let rec bench l n =
  if n <= 0 then
    l
  else
    let (diff, pid) = time start "tap0" in
    let _ = stop pid in
    bench (diff :: l) (n-1)

let () = 
  let num_times = Sys.argv.(1) |> int_of_string in
  let l = bench [] num_times in
  let times = List.map Mtime.Span.to_us l |> Array.of_list in
  let mean = Owl_base_stats.mean times in
  let std = Owl_base_stats.std ~mean times in
  Printf.printf "%d runs:\n\tMean = %fus\n\tStd  = %fus\n" num_times mean std
