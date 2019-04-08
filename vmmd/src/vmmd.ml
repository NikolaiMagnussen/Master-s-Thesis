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

let level_table =
  let tbl = Hashtbl.create 0 in
  let a = ("<\"TopSecret\">", "TopSecret") in
  let b = ("<\"Secret\">", "Secret") in
  let c = ("<\"Confidential\">", "Confidential") in
  let d = ("<\"Unclassified\">", "Unclassified") in
  let s = List.to_seq [a; b; c; d] in
  Hashtbl.add_seq tbl s;
  tbl

let transform_level level =
  Hashtbl.find level_table level

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

let del_unikernel name =
  Hashtbl.remove unikernels name

let upsert_unikernel name path hvt level =
  let unikernel = {
    name = name;
    path = path;
    hvt = hvt;
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
  Bos.OS.Cmd.run Bos.Cmd.(v "ip" % "link" % "set" % "dev" % tap % "up") >|> fun () ->
  Ok tap

let spawn_level kernel level =
  let unikernel = Hashtbl.find unikernels kernel in
  new_tap "br0" >|> fun tap ->
  let hvt = Fpath.to_string unikernel.hvt in
  let path = Fpath.to_string unikernel.path in
  let tap_number = int_of_string (String.sub tap 3 ((String.length tap) - 3)) in
  let ip_addr = Printf.sprintf "10.0.0.%d/24" (tap_number + 2) in
  let pid = Unix.create_process hvt [|hvt; "--net="^tap; path; "--ipv4="^ip_addr; "--capability="^level|] Unix.stdin Unix.stdout Unix.stderr in
  add_running kernel level pid >|> fun uuid ->
  Ok (uuid, ip_addr, level)

let spawn kernel =
  let unikernel = Hashtbl.find unikernels kernel in
  spawn_level kernel (unikernel.default)

let stop uuid =
  Option.(
    Hashtbl.find_opt running uuid >>= fun unikernel ->
    let pid = unikernel.pid in
    Unix.kill pid Sys.sigterm;
    let (_, status) = Unix.waitpid [] pid in
    let msg = match status with
      | Unix.WEXITED s -> Printf.sprintf "WEXITED(%d)" s
      | Unix.WSIGNALED s -> Printf.sprintf "WSIGNALED(%d)" s
      | Unix.WSTOPPED s -> Printf.sprintf "WSTOPPED(%d)" s
    in
    Hashtbl.remove running uuid;
    return msg
  )

(*
 * Register should:
   * Derive hvt path from path, and add it to the table
   * For later development, we should copy the files into a directory
 *)
let register name path level = 
  Fpath.of_string path  >|> fun path ->
  let hvt_name = "solo5-hvt" in
  let dir = Fpath.parent path in
  let hvt = Fpath.(dir / hvt_name) in
  upsert_unikernel name path hvt level;
  Ok ()

(** HANDLER FUNCTIONS - These should invoke all functionality **)
let register_unikernel = post "/" begin fun req ->
    extract_body req >>=
    fun (name, path, level) ->
    let code = match register name path level with
      | Error _ -> `Not_found
      | Ok _ -> `OK
    in
    `String ("registered or updated unikernel " ^ name ^ " with default level: " ^ level) |> respond' ~code
  end

let update_unikernel = put "/" begin fun req ->
    extract_body req >>=
    fun (name, path, level) ->
    let code = match register name path level with
      | Error _ -> `Not_found
      | Ok _ -> `OK
    in
    `String ("updated or registered unikernel " ^ name ^ " with default level: " ^ level) |> respond' ~code
  end

let delete_unikernel = delete "/:name" begin fun req ->
    let name = param req "name" in
    del_unikernel name;
    `String ("deleted unikernel " ^ name) |> respond'
  end

let list_unikernels = get "/" begin fun _req ->
    let transform_unikernel = fun (_name, {name; path; hvt; default}) ->
      let path = Fpath.to_string path in
      let hvt = Fpath.to_string hvt in
      Printf.sprintf "[UNIKERNEL] name: %s, path: %s, hvt: %s, default: %s\n" name path hvt default
    in
    let transform_running = fun (_id, {name; pid; level; id}) ->
      Printf.sprintf "[RUNNING] id: %s, name: %s, pid: %d, level: %s\n" id name pid level
    in
    let unikernel_seq = Seq.map transform_unikernel (Hashtbl.to_seq unikernels) in
    let running_seq = Seq.map transform_running (Hashtbl.to_seq running) in
    let unikernel_str = Seq.fold_left (^) "" unikernel_seq in
    let running_str = Seq.fold_left (^) "" running_seq in
    `String (unikernel_str ^ running_str) |> respond'
  end

(*
  Ok (uuid, ip_addr, level)
 *)
let start_unikernel = get "/start/:name" begin fun req ->
    let name = param req "name" in
    let (code, body) = match spawn name with
      | Error _ -> (`Not_found, `String "")
      | Ok (uuid, ip_addr, level) ->
        let body = Printf.sprintf "{\"uuid\": \"%s\", \"ip_addr\": \"%s\", \"level\": \"%s\"}" uuid ip_addr level 
                   |> Ezjsonm.from_string
        in (`OK, `Json body)
    in respond' ~code body
  end

let start_unikernel_level = get "/start/:name/:level" begin fun req ->
    let name = param req "name" in
    let level = "level" |> param req |> transform_level in
    let (code, body) = match spawn_level name level with
      | Error _ -> (`Not_found, `String "")
      | Ok (uuid, ip_addr, level) ->
        let body = Printf.sprintf "{\"uuid\": \"%s\", \"ip_addr\": \"%s\", \"level\": \"%s\"}" uuid ip_addr level 
                   |> Ezjsonm.from_string
        in (`OK, `Json body)
    in respond' ~code body
  end

let stop_unikernel = get "/stop/:id" begin fun req ->
    let id = param req "id" in
    let (body, code) = match stop id with
      | None -> ("was not properly killed", `Not_found)
      | Some b -> (b, `OK)
    in
    `String ("stop unikernel " ^ id ^ " with text: " ^ body) |> respond' ~code
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
