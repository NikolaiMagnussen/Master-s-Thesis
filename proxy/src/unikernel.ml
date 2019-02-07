open Lwt
open Cohttp
open Cohttp_mirage
open Capability_t

module Proxy (CON : Conduit_mirage.S) = struct
  module S = Cohttp_mirage.Server(Conduit_mirage.Flow)

  let add_entry (host:string) ip_str table =
    let ip = Ipaddr.of_string_exn ip_str in
    Hashtbl.add table host (fun ~(port:int) -> (`TCP (ip, port) : Conduit.endp))

  let route_table = let tbl = Hashtbl.create 3 in
    add_entry "proxy.local" "10.0.0.2" tbl;
    add_entry "auth.local" "10.0.0.3" tbl;
    add_entry "static.local" "10.0.0.4" tbl;
    tbl

  let static_resolver table = Resolver_mirage.static table
  let ctx conduit = Cohttp_mirage.Client.ctx (static_resolver route_table) conduit

  let build_uri host path =
    Uri.of_string (Printf.sprintf "http://%s:8000%s" host path)

  let get_capabilities headers ctx =
    let uri = build_uri "auth.local" "/" in
    Client.get ~ctx uri ~headers >>= fun (resp, _body) ->
    let headers = Response.headers resp in
    let cap = match Header.get headers "capability" with
      | Some cap -> Capability_j.capability_of_string cap
      | None -> `None 
    in Lwt.return cap

  let register_service headers =
    let ip = Header.get headers "ip-addr" in
    let cap = Header.get headers "capability" in
    match (ip, cap) with
    | (Some ip, Some cap) ->
      add_entry cap ip route_table;
      S.respond ~status: `Accepted ~body: `Empty ()
    | (_, _) -> S.respond ~status: `Unprocessable_entity ~body: `Empty ()

  let get_routing_table () =
    let keys = Hashtbl.to_seq route_table in
    let map_keys_to_str prev_str key =
      let endp = match (snd key) ~port:8000 with
        | `TCP (ip, port) -> Printf.sprintf "%s:%d" (Ipaddr.to_string ip) port
        | _ -> "unknown"
      in
      Printf.sprintf "%s(%s, %s)\n" prev_str (fst key) endp
    in
    Seq.fold_left map_keys_to_str "" keys

  let handle path meth headers body conduit =
    let uri = build_uri "static.local" path in
    let ctx = ctx conduit in
    get_capabilities headers ctx >>= fun cap ->
    match (meth, path) with
    | (`GET, "/register") -> register_service headers
    | (`GET, "/routes") -> S.respond_string ~status: `OK ~body: (get_routing_table ()) ()
    | (`GET, _) -> Client.get ~ctx uri
    | (`POST, _) -> Client.post ~ctx ~body uri
    | _ -> Client.get ~ctx uri
      >>= fun (resp, body) ->
      S.respond_string ~status: `OK ~body: "kake er godt" ()

  let start conduit =
    let callback _conn req body =
      let path = req |> Request.uri |> Uri.path in
      let meth = Request.meth req in
      let headers = Request.headers req in
      handle path meth headers body conduit
    in
    let spec = S.make ~callback () in
    CON.listen conduit (`TCP (Key_gen.port ())) (S.listen spec)
end
