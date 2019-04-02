open Lwt
open Cohttp
open Cohttp_mirage
open Capability_t

module Auth (CON : Conduit_mirage.S) = struct
  module S = Cohttp_mirage.Server(Conduit_mirage.Flow)

  (* Can't use Argon2 due to not being able to compile under MirageOS *
     type creds = {
     encoded: Argon2.encoded;
     clearence: capability;
     }

     let some_creds : (string * creds) list =
     [
      ("dummy", {encoded="$argon2i$v=19$m=4096,t=3,p=1$aVk0Y1F0Kys$Ng7qqfVcjhUZYvRf4RwTXC0rA+T5/UJEXpTkEHWCJoc"; clearence=`Unclassified});
      ("admin", {encoded="$argon2i$v=19$m=4096,t=3,p=1$Y3hFWTljRkI$clx78rvof7J062PIf7Rmvn+FDTPn7kc1qQ0oA/MgEns"; clearence=`TopSecret});
     ]

     let default_creds =
     let creds = List.to_seq some_creds in
     Hashtbl.of_seq creds

     let verify_user user pwd =
     let {encoded; clearence} = Hashtbl.find default_creds user in
     let kind = Argon2.I in
     match Argon2.verify ~encoded ~pwd ~kind with
     | Ok res -> (res, clearence)
     | Error _e -> (false, clearence)
  *)

  let scrypt_hash pass salt =
    let password = Cstruct.of_string pass in
    let salt = Cstruct.of_string salt in
    let n = 1 lsl 15 in
    let r = 8 in
    let p = 1 in
    let dk_len = Int32.of_int 32 in
    Scrypt_kdf.scrypt_kdf ~password ~salt ~n ~r ~p ~dk_len

  let creds : (string, (capability * string * Cstruct.t)) Hashtbl.t =
    [
      ("dummy", "password123", "iY4cQt++", `Unclassified);
      ("admin", "password123", "cxEY9cFB", `TopSecret);
    ]
    |> List.map (fun (user, pass, salt, clear) -> (user, (clear, salt, scrypt_hash pass salt)))
    |> List.to_seq
    |> Hashtbl.of_seq

  let scrypt_verify username pass =
    let (clearence, salt, hash) = Hashtbl.find creds username in
    let res = scrypt_hash pass salt in
    let equal = Cstruct.equal res hash in
    (equal, clearence)

  let token_map =
    let tbl = Hashtbl.create 0 in
    Hashtbl.add tbl "4a183696-c4cc-48fe-90b9-831147ec12a2" `Unclassified;
    Hashtbl.add tbl "fefb7751-7893-435e-82fd-25f0becb3c64" `TopSecret;
    tbl

  let unauthorized_login =
    let headers = Header.init_with "www-authenticate" "Bearer realm=\"proxy.local\"" in
    S.respond ~headers ~status: `Unauthorized ~body: `Empty

  let check_token token =
    match Hashtbl.find_opt token_map token with
    | Some cap -> let headers = Header.init_with "capabilities" (Capability_j.string_of_capability cap) in
      S.respond ~status: `OK ~headers ~body: `Empty ()
    | None -> unauthorized_login ()

  let handle_token token =
    match String.split_on_char ' ' token with
    | "Bearer" :: content_l -> 
      let content = String.concat "" content_l in
      check_token content
    | _ -> unauthorized_login ()

  let handle path meth headers body conduit =
    match Header.get_authorization headers with
    | Some `Other token -> handle_token token
    | Some `Basic _ | None -> let headers = Header.init_with "www-authenticate" "Bearer realm=\"proxy.local\"" in
      S.respond ~headers ~status: `Unauthorized ~body: `Empty ()

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
