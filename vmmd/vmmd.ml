open Rresult
open Opium.Std
open Lwt.Infix

let new_tap br =
  let rec free_tap n =
    let tap_name = "tap" ^ string_of_int n in
    match Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "addr" % "show" % "dev" % tap_name) with
    | Error _ -> tap_name
    | Ok _ -> free_tap (succ n)
  in
  let tap = free_tap 0 in
  match Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "tuntap" % "add" % tap % "mode" % "tap") with
  | Error a -> Error a
  | Ok _ ->
    match Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "link" % "set" % tap % "master" % br) with
    | Error a -> Error a
    | Ok _ -> Ok tap

let spawn kernel =
  match new_tap "br0" with
  | Error a -> Error a
  | Ok tap -> Bos.OS.Cmd.run Bos.Cmd.(v "ls" % tap % kernel)

let spawn_level kernel level =
  match new_tap "br0" with
  | Error a -> Error a
  | Ok tap -> Bos.OS.Cmd.run Bos.Cmd.(v "ls" % tap % kernel % level)

let stop id =
  Bos.OS.Cmd.run Bos.Cmd.(v "ls" % id)

(* Things we need to do:
 * - Create new tap
 * - Spawn unikernel and attach the network tap
 * - Stop unikernel
 * - Destroy tap device
*)

type unikernel = {
  name: string;
  path: Fpath.t;
  default: string;
}

type running = {
  name: string;
  level: string;
  id: string;
}

let unikernels = Hashtbl.create 1
let running = Hashtbl.create 1

let add_running name level =
  if Hashtbl.mem unikernels name then
    let id = Uuidm.(to_string (create `V4)) in
    let kernel = {
      name = name;
      level = level;
      id = id;
    } in
    Hashtbl.add running id kernel;
    Some id
  else
    None

let add_unikernel name path level =
  let unikernel = {
    name = name;
    path = path;
    default = level;
  } in
  Hashtbl.add unikernels name unikernel

let del_unikernel name =
  Hashtbl.remove unikernels name

let edit_unikernel name path level =
  let unikernel = {
    name = name;
    path = path;
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
    let transform = fun (_name, {name; path; default}) ->
      "name: " ^ name ^ ", path: " ^ (Fpath.to_string path) ^ ", default: " ^ default
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
      | Error _ -> `Not_found
      | Ok _ -> `OK
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
