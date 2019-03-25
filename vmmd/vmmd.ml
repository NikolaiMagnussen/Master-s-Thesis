open Rresult
open Opium.Std
open Lwt.Infix

type unikernel = {
  name: string;
  path: Fpath.t;
  hvt: Fpath.t;
  default: string;
}

type running = {
  name: string;
  pid: int;
  level: string;
  id: string;
}

module Option = struct
  type 'a t = 'a option
  let return x = Some x
  let bind m f =
    match m with
    | Some x -> f x
    | None -> None
  let (>>=) = bind
end

let unikernels = Hashtbl.create 1
let running = Hashtbl.create 1

(* Redefine >>= for Rresult *)
let (>|>) a b = Rresult.(a >>= b)

let add_running name level pid =
  if Hashtbl.mem unikernels name then
    let id = Uuidm.(to_string (create `V4)) in
    let kernel = {
      level = level;
      name = name;
      pid = pid;
      id = id;
    } in
    Hashtbl.add running id kernel;
    Ok id
  else
    Error (Rresult.R.msg "Did not find unikernel by that name")

let add_unikernel name path level =
  let unikernel = {
    name = name;
    path = path;
    hvt = path;
    default = level;
  } in
  Hashtbl.add unikernels name unikernel

let del_unikernel name =
  Hashtbl.remove unikernels name

let edit_unikernel name path level =
  let unikernel = {
    name = name;
    path = path;
    hvt = path;
    default = level;
  } in
  Hashtbl.replace unikernels name unikernel

let extract_body req =
  App.json_of_body_exn req |> Lwt.map (fun json ->
      let json = Ezjsonm.value json in
      let name = Ezjsonm.(get_string (find json ["name"])) in
      let path = Ezjsonm.(get_string (find json ["path"])) in
      let level = Ezjsonm.(get_string (find json ["level"])) in
      (name, path, level))

let new_tap br =
  let rec free_tap n =
    let tap_name = "tap" ^ string_of_int n in
    match Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "addr" % "show" % "dev" % tap_name) with
    | Error _ -> tap_name
    | Ok _ -> free_tap (succ n)
  in
  let tap = free_tap 0 in
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "tuntap" % "add" % tap % "mode" % "tap") >|> fun () ->
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "link" % "set" % tap % "master" % br) >|> fun () ->
  Ok tap

let spawn_level kernel level =
  let unikernel = Hashtbl.find unikernels kernel in
  new_tap "br0" >|> fun tap ->
  let hvt = Fpath.to_string unikernel.hvt in
  let path = Fpath.to_string unikernel.path in
  let pid = Unix.create_process hvt [|"--net"; tap; path|] Unix.stdin Unix.stdout Unix.stderr in
  add_running kernel level pid >|> fun uuid ->
  Ok uuid

let spawn kernel =
  let unikernel = Hashtbl.find unikernels kernel in
  spawn_level kernel (unikernel.default)

let stop uuid =
  Option.(
    Hashtbl.find_opt running uuid >>= fun unikernel ->
    let pid = unikernel.pid in
    Unix.kill pid Sys.sigterm;
    return ()
  )

(* Things we need to do:
 * - Create new tap
 * - Spawn unikernel and attach the network tap
 * - Stop unikernel
 * - Destroy tap device
*)

let register_unikernel = post "/" begin fun req ->
    extract_body req >>=
    fun (_name, _path, _level) ->
    `String "kake er godt" |> respond'
  end

let update_unikernel = put "/:name" begin fun req ->
    extract_body req >>=
    fun (name, _path, _level) ->
    `String ("update unikernel " ^ name) |> respond'
  end

let delete_unikernel = delete "/:name" begin fun req ->
    `String ("delete unikernel " ^ param req "name") |> respond'
  end

let list_unikernels = get "/" begin fun _req ->
    let transform = fun (_name, {name; path; hvt; default}) ->
      let path = Fpath.to_string path in
      let hvt = Fpath.to_string hvt in
      Printf.sprintf "name: %s, path: %s, hvt: %s, default: %s" name path hvt default
    in
    let str_seq = Seq.map transform (Hashtbl.to_seq unikernels) in
    let unikernel_str = Seq.fold_left (^) "" str_seq in
    `String unikernel_str |> respond'
  end

let start_unikernel = get "/start/:name" begin fun req ->
    let name = param req "name" in
    let code = match spawn name with
      | Error _ -> `Not_found
      | Ok _ -> `OK
    in
    `String ("start unikernel " ^ name ^ " with default level") |> respond' ~code
  end

let start_unikernel_level = get "/start/:name/:level" begin fun req ->
    let name = param req "name" in
    let level = param req "level" in
    let code = match spawn_level name level with
      | Error _ -> `Not_found
      | Ok _ -> `OK
    in
    `String ("start unikernel " ^ name ^ " with level " ^ level) |> respond' ~code
  end

let stop_unikernel = get "/stop/:id" begin fun req ->
    let id = param req "id" in
    let code = match stop id with
      | None -> `Not_found
      | Some _ -> `OK
    in
    `String ("stop unikernel " ^ id) |> respond' ~code
  end

let () =
  App.empty
  |> register_unikernel
  |> update_unikernel
  |> delete_unikernel
  |> list_unikernels
  |> start_unikernel
  |> start_unikernel_level
  |> stop_unikernel
  |> App.run_command
