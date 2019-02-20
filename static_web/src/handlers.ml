open Lwt
open Cohttp
open Cohttp_mirage

module Handlers = struct
  let static_page _body _headers _conduit =
    Lwt.return (`OK, "This is a static string", [])

  let add_entry (host:string) ip_str table =
    let ip = Ipaddr.of_string_exn ip_str in
    Hashtbl.add table host (fun ~(port:int) -> (`TCP (ip, port) : Conduit.endp))

  let route_table =
    let tbl = Hashtbl.create 1 in
    add_entry "proxy.local" "10.0.0.2" tbl;
    tbl

  let static_resolver table = Resolver_mirage.static table
  let ctx conduit = Cohttp_mirage.Client.ctx (static_resolver route_table) conduit

  let build_uri host path =
    Uri.of_string (Printf.sprintf "http://%s:8000%s" host path)

  let register_to_loadbalancer conduit =
    let uri = build_uri "proxy.local" "/register" in
    let ctx = ctx conduit in
    let headers = Header.init_with "ip-addr" (Ipaddr.V4.to_string (snd (Key_gen.ipv4()))) in
    let headers = Header.add headers "capability" (Key_gen.capability()) in
    Client.get ~ctx ~headers uri >>= fun (_resp, _body) ->
    Lwt.return_unit
end
