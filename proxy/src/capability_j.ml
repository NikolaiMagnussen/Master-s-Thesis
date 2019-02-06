(* Auto-generated from "capability.atd" *)
[@@@ocaml.warning "-27-32-35-39"]

type capability = Capability_t.capability

let write_capability = (
  fun ob x ->
    match x with
      | `None -> Bi_outbuf.add_string ob "<\"None\">"
      | `Unclassified -> Bi_outbuf.add_string ob "<\"Unclassified\">"
      | `Restricted -> Bi_outbuf.add_string ob "<\"Restricted\">"
      | `Confidential -> Bi_outbuf.add_string ob "<\"Confidential\">"
      | `Secret -> Bi_outbuf.add_string ob "<\"Secret\">"
      | `TopSecret -> Bi_outbuf.add_string ob "<\"TopSecret\">"
)
let string_of_capability ?(len = 1024) x =
  let ob = Bi_outbuf.create len in
  write_capability ob x;
  Bi_outbuf.contents ob
let read_capability = (
  fun p lb ->
    Yojson.Safe.read_space p lb;
    match Yojson.Safe.start_any_variant p lb with
      | `Edgy_bracket -> (
          match Yojson.Safe.read_ident p lb with
            | "None" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `None
            | "Unclassified" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `Unclassified
            | "Restricted" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `Restricted
            | "Confidential" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `Confidential
            | "Secret" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `Secret
            | "TopSecret" ->
              Yojson.Safe.read_space p lb;
              Yojson.Safe.read_gt p lb;
              `TopSecret
            | x ->
              Atdgen_runtime.Oj_run.invalid_variant_tag p x
        )
      | `Double_quote -> (
          match Yojson.Safe.finish_string p lb with
            | "None" ->
              `None
            | "Unclassified" ->
              `Unclassified
            | "Restricted" ->
              `Restricted
            | "Confidential" ->
              `Confidential
            | "Secret" ->
              `Secret
            | "TopSecret" ->
              `TopSecret
            | x ->
              Atdgen_runtime.Oj_run.invalid_variant_tag p x
        )
      | `Square_bracket -> (
          match Atdgen_runtime.Oj_run.read_string p lb with
            | x ->
              Atdgen_runtime.Oj_run.invalid_variant_tag p x
        )
)
let capability_of_string s =
  read_capability (Yojson.Safe.init_lexer ()) (Lexing.from_string s)
