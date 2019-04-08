open Lwt
open Cohttp_lwt
open Cohttp_mirage
open Capability_t

module Proxy (CON : Conduit_mirage.S) = struct
  module S = Cohttp_mirage.Server(Conduit_mirage.Flow)

  let add_entry (host:string) ip_str table =
    let ip = Ipaddr.of_string_exn ip_str in
    Hashtbl.add table host (fun ~(port:int) -> (`TCP (ip, port) : Conduit.endp))

  let text_table =
    let tbl = Hashtbl.create 6 in
    Hashtbl.add tbl "None" `None;
    Hashtbl.add tbl "Unclassified" `Unclassified;
    Hashtbl.add tbl "Restricted" `Restricted;
    Hashtbl.add tbl "Confidential" `Confidential;
    Hashtbl.add tbl "Secret" `Secret;
    Hashtbl.add tbl "TopSecret" `TopSecret;
    tbl

  let round_robin =
    let tbl = Hashtbl.create 6 in
    Hashtbl.add tbl `None (0, 0, []);
    Hashtbl.add tbl `Unclassified (0, 0, []);
    Hashtbl.add tbl `Restricted (0, 0, []);
    Hashtbl.add tbl `Confidential (0, 0, []);
    Hashtbl.add tbl `Secret (0, 0, []);
    Hashtbl.add tbl `TopSecret (0, 0, []);
    tbl

  let route_table =
    let tbl = Hashtbl.create 3 in
    add_entry "proxy.local" "10.0.0.2" tbl;
    add_entry "auth.local" "10.0.0.3" tbl;
    add_entry "static.local" "10.0.0.4" tbl;
    add_entry "vmmd.local" "129.242.181.244" tbl;
    tbl

  let dynamic_table =
    Hashtbl.create 1

  let add_dynamic uuid host =
    Hashtbl.add dynamic_table uuid host

  let static_resolver table = Resolver_mirage.static table
  let ctx conduit = Cohttp_mirage.Client.ctx (static_resolver route_table) conduit

  let build_uri host path =
    Uri.of_string (Printf.sprintf "http://%s:8000%s" host path)

  let get_capabilities headers ctx =
    let uri = build_uri "auth.local" "/" in
    Client.get ~ctx uri ~headers >>= fun (resp, _body) ->
    let headers = Response.headers resp in
    let cap = match Cohttp.Header.get headers "capabilities" with
      | Some cap -> Capability_j.capability_of_string cap
      | None -> `None 
    in Lwt.return cap

  let hostname_of_cap cap num =
    let cap_str = Capability_j.string_of_capability cap in
    let cap = match String.split_on_char '"' cap_str with
      | _ :: cap :: _ -> cap
      | _ -> "None"
    in
    Printf.sprintf "%s%d.local" (String.lowercase_ascii cap) num

  let add_cap_entry cap =
    let (next, len, hosts) = Hashtbl.find round_robin cap in
    let new_host = hostname_of_cap cap len in
    Hashtbl.replace round_robin cap (next, len+1, new_host::hosts);
    new_host

  let register_service headers =
    let ip = Cohttp.Header.get headers "ip-addr" in
    let cap = Cohttp.Header.get headers "capability" in
    match (ip, cap) with
    | (Some ip, Some cap) ->
      let capability = Capability_j.capability_of_string cap in
      let new_host = add_cap_entry capability in
      add_entry new_host ip route_table;
      S.respond ~status: `Accepted ~body: `Empty ()
    | (_, _) -> S.respond ~status: `Bad_request ~body: `Empty ()

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

  let get_round_robin_table () =
    let kv = Hashtbl.to_seq round_robin in
    let map_kv_to_str prev_str (k, (n, l, vs)) =
      let v_str = List.fold_left (Printf.sprintf "%s, %s") "" vs in
      Printf.sprintf "%s%s -> (%d, %d, %s)\n" prev_str (Capability_j.string_of_capability k) n l v_str
    in
    Seq.fold_left map_kv_to_str "" kv

  let get_cap_host cap robin_table =
    let (curr, len, hosts) = Hashtbl.find robin_table cap in
    if len > 0 then
      let next = (curr + 1) mod len in
      Hashtbl.replace robin_table cap (next, len, hosts);
      Some (List.nth hosts (curr mod len))
    else
      None

  (*
  let kill_unikernel uuid level ctx =
    Client.get ~ctx (build_uri "vmmd.local" ("/stop/" ^ uuid)) >>= fun _ ->
    let host = Hashtbl.find dynamic_table uuid in
    Hashtbl.remove dynamic_table uuid;
    let (n, i, l) = Hashtbl.find round_robin level in
    let l = List.filter (fun x -> String.equal x host |> not) l in
    Hashtbl.replace round_robin level (n, i, l);
    Hashtbl.remove route_table host;
    Lwt.return_unit
  *)

  let forward_response (resp, body) =
    let status = Response.status resp in
    S.respond ~status ~body ()

  let wait_and_forward (resp, body) ctx path cap round_robin =
    Body.to_string body >>= fun js ->
    let json = Ezjsonm.from_string js in
    let uuid = Ezjsonm.(get_string (find json ["uuid"])) in
    let ip_addr = Ezjsonm.(get_string (find json ["ip_addr"])) in
    let level = Ezjsonm.(get_string (find json ["level"])) |> Hashtbl.find text_table in
    let new_host = add_cap_entry level in
    add_entry new_host Ipaddr.(of_string_exn ip_addr |> to_string) route_table;
    add_dynamic uuid new_host;
    match get_cap_host level round_robin with
    | Some host ->
      let rec req host =
        Client.get ~ctx (build_uri host path) >>= fun (resp, body) ->
        match Cohttp.(Response.status resp |> Code.code_of_status |> Code.is_success) with
        | true -> forward_response (resp, body)
        | false -> req host
      in
      req host
    | None ->
      S.respond_not_found ()

  let handle path meth headers body conduit =
    let ctx = ctx conduit in
    get_capabilities headers ctx >>= fun cap ->
    let host = get_cap_host cap round_robin in
    match (meth, path, host) with
    | (`GET, "/register", _) -> register_service headers
    | (`GET, "/routes", _) -> S.respond_string ~status: `OK ~body: (get_routing_table ()) ()
    | (`GET, "/robin", _) -> S.respond_string ~status: `OK ~body: (get_round_robin_table ()) ()
    | (`GET, _, Some host) -> Client.get ~ctx (build_uri host path) >>= forward_response
    | (`POST, _, Some host) -> Client.post ~ctx ~body (build_uri host path) >>= forward_response
    | _ -> Client.get ~ctx (build_uri "vmmd.local" ("/start" ^ path ^ "/" ^ Capability_j.string_of_capability cap)) >>=
      fun res -> wait_and_forward res ctx path cap round_robin

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
