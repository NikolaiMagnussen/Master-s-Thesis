open Rresult
open Lwt
open Cohttp
open Cohttp_lwt_unix

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

(* Things we need to do:
 * - Create new tap
 * - Spawn unikernel and attach the network tap
 * - Stop unikernel
 * - Destroy tap device
*)

let server =
  let callback _conn req body =
    let uri = req |> Request.uri |> Uri.to_string in
    let meth = req |> Request.meth |> Code.string_of_method in
    let headers = req |> Request.headers |> Header.to_string in
    body |> Cohttp_lwt.Body.to_string >|= (fun body ->
        (Printf.sprintf "Uri: %s\nMethod: %s\nHeaders: %s\nBody: %s"
           uri meth headers body))
    >>= (fun body -> Server.respond_string ~status:`OK ~body ())
  in
  Server.create ~mode: (`TCP (`Port 8000)) (Server.make ~callback ())

let () = ignore (Lwt_main.run server)
