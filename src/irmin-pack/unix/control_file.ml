(*
 * Copyright (c) 2022-2022 Tarides <contact@tarides.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Import
include Control_file_intf
module Version = Irmin_pack.Version

module Checksum = struct
  let calculate ~encode_bin ~set_checksum ~payload =
    let open Checkseum in
    let result = ref Adler32.default in
    encode_bin (set_checksum payload Int63.zero) (fun str ->
        result := Adler32.digest_string str 0 (String.length str) !result);
    Int63.of_int (Optint.to_int !result)

  let calculate_and_set ~encode_bin ~set_checksum ~payload =
    calculate ~encode_bin ~set_checksum ~payload |> set_checksum payload

  let is_valid ~encode_bin ~set_checksum ~get_checksum ~payload =
    Int63.equal
      (calculate ~encode_bin ~set_checksum ~payload)
      (get_checksum payload)
end

module Serde = struct
  module type S = sig
    type payload

    val of_bin_string :
      string ->
      ( payload,
        [> `Corrupted_control_file | `Unknown_major_pack_version of string ] )
      result

    val to_bin_string : payload -> string
  end

  let extract_version_and_payload s =
    let open Result_syntax in
    let len = String.length s in
    let* left, right =
      try Ok (String.sub s 0 8, String.sub s 8 (len - 8))
      with Invalid_argument _ -> Error `Corrupted_control_file
    in
    let+ version =
      match Version.of_bin left with
      | None -> Error (`Unknown_major_pack_version left)
      | Some (`V1 | `V2) -> assert false (* TODO: create specific error *)
      | Some ((`V3 | `V4 | `V5) as x) ->
          if len > Io.Unix.page_size then
            (* TODO: make this a more specific error *)
            Error `Corrupted_control_file
          else Ok x
    in
    (version, right)

  module Upper : S with type payload = Payload.Upper.Latest.t = struct
    module Data = struct
      module Plv3 = struct
        include Payload.Upper.V3

        let of_bin_string = Irmin.Type.(unstage (of_bin_string t))
      end

      module Plv4 = struct
        include Payload.Upper.V4

        let is_checksum_valid payload =
          let encode_bin = Irmin.Type.(unstage (pre_hash t)) in
          let set_checksum payload checksum = { payload with checksum } in
          let get_checksum payload = payload.checksum in
          Checksum.is_valid ~payload ~encode_bin ~set_checksum ~get_checksum

        let of_bin_string = Irmin.Type.(unstage (of_bin_string t))
      end

      module Plv5 = struct
        include Payload.Upper.V5

        let checksum_encode_bin = Irmin.Type.(unstage (pre_hash t))
        let set_checksum payload checksum = { payload with checksum }
        let get_checksum payload = payload.checksum

        let is_checksum_valid payload =
          Checksum.is_valid ~payload ~encode_bin:checksum_encode_bin
            ~set_checksum ~get_checksum

        let set_checksum payload =
          Checksum.calculate_and_set ~encode_bin:checksum_encode_bin
            ~set_checksum ~payload

        let of_bin_string = Irmin.Type.(unstage (of_bin_string t))
        let to_bin_string = Irmin.Type.(unstage (to_bin_string t))
      end

      type t = Valid of version | Invalid of version
      and version = V3 of Plv3.t | V4 of Plv4.t | V5 of Plv5.t

      let to_bin_string = function
        | Invalid _ | Valid (V3 _) | Valid (V4 _) -> assert false
        | Valid (V5 payload) ->
            let payload = Plv5.set_checksum payload in
            Version.to_bin `V5 ^ Plv5.to_bin_string payload

      let of_bin_string s =
        let open Result_syntax in
        let* version, payload = extract_version_and_payload s in
        let route_version () =
          match version with
          | `V3 ->
              Plv3.of_bin_string payload >>= fun payload ->
              Valid (V3 payload) |> Result.ok
          | `V4 ->
              Plv4.of_bin_string payload >>= fun payload ->
              (match Plv4.is_checksum_valid payload with
              | false -> Invalid (V4 payload)
              | true -> Valid (V4 payload))
              |> Result.ok
          | `V5 ->
              Plv5.of_bin_string payload >>= fun payload ->
              (match Plv5.is_checksum_valid payload with
              | false -> Invalid (V5 payload)
              | true -> Valid (V5 payload))
              |> Result.ok
        in
        match route_version () with
        | Ok _ as x -> x
        | Error _ -> Error `Corrupted_control_file
    end

    module Latest = Data.Plv5

    type payload = Latest.t

    let upgrade_from_v3 (pl : Payload.Upper.V3.t) : payload =
      let chunk_start_idx = ref 0 in
      let status =
        match pl.status with
        | From_v1_v2_post_upgrade x -> Latest.From_v1_v2_post_upgrade x
        | From_v3_no_gc_yet -> No_gc_yet
        | From_v3_used_non_minimal_indexing_strategy ->
            Used_non_minimal_indexing_strategy
        | From_v3_gced x ->
            chunk_start_idx := x.generation;
            Gced
              {
                suffix_start_offset = x.suffix_start_offset;
                generation = x.generation;
                latest_gc_target_offset = x.suffix_start_offset;
                suffix_dead_bytes = Int63.zero;
              }
        | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | T9 | T10 | T11 | T12 | T13
        | T14 | T15 ->
            (* Unreachable *)
            assert false
      in
      {
        dict_end_poff = pl.dict_end_poff;
        (* When upgrading from v3 to v4, there is only one (appendable) chunk,
           which is the existing suffix, so we set the new [appendable_chunk_poff]
           to [pl.suffix_end_poff]. *)
        appendable_chunk_poff = pl.suffix_end_poff;
        status;
        upgraded_from = Some (Version.to_int `V3);
        checksum = Int63.zero;
        chunk_start_idx = !chunk_start_idx;
        chunk_num = 1;
        volume_num = 0;
      }

    let upgrade_from_v4 (pl : Payload.Upper.V4.t) : payload =
      {
        dict_end_poff = pl.dict_end_poff;
        appendable_chunk_poff = pl.appendable_chunk_poff;
        checksum = Int63.zero;
        chunk_start_idx = pl.chunk_start_idx;
        chunk_num = pl.chunk_num;
        status = pl.status;
        upgraded_from = Some (Version.to_int `V4);
        volume_num = 0;
      }

    let of_bin_string string =
      let open Result_syntax in
      let* payload = Data.of_bin_string string in
      match payload with
      | Invalid _ -> Error `Corrupted_control_file
      | Valid (V3 payload) -> Ok (upgrade_from_v3 payload)
      | Valid (V4 payload) -> Ok (upgrade_from_v4 payload)
      | Valid (V5 payload) -> Ok payload

    let to_bin_string payload = Data.(to_bin_string (Valid (V5 payload)))
  end

  module Volume : S with type payload = Payload.Volume.Latest.t = struct
    module Data = struct
      module Plv5 = struct
        include Payload.Volume.V5

        let checksum_encode_bin = Irmin.Type.(unstage (pre_hash t))
        let set_checksum payload checksum = { payload with checksum }
        let get_checksum payload = payload.checksum

        let is_checksum_valid payload =
          Checksum.is_valid ~payload ~encode_bin:checksum_encode_bin
            ~set_checksum ~get_checksum

        let set_checksum payload =
          Checksum.calculate_and_set ~encode_bin:checksum_encode_bin
            ~set_checksum ~payload

        let of_bin_string = Irmin.Type.(unstage (of_bin_string t))
        let to_bin_string = Irmin.Type.(unstage (to_bin_string t))
      end

      type t = Valid of version | Invalid of version
      and version = V5 of Plv5.t

      let to_bin_string = function
        | Invalid _ -> assert false
        | Valid (V5 payload) ->
            let payload = Plv5.set_checksum payload in
            Version.to_bin `V5 ^ Plv5.to_bin_string payload

      let of_bin_string s =
        let open Result_syntax in
        let* version, payload = extract_version_and_payload s in
        let route_version () =
          match version with
          | `V3 | `V4 -> assert false
          | `V5 ->
              Plv5.of_bin_string payload >>= fun payload ->
              (match Plv5.is_checksum_valid payload with
              | false -> Invalid (V5 payload)
              | true -> Valid (V5 payload))
              |> Result.ok
        in
        match route_version () with
        | Ok _ as x -> x
        | Error _ -> Error `Corrupted_control_file
    end

    module Payload = Data.Plv5

    type payload = Payload.t

    let of_bin_string string =
      let open Result_syntax in
      let* payload = Data.of_bin_string string in
      match payload with
      | Invalid _ -> Error `Corrupted_control_file
      | Valid (V5 payload) -> Ok payload

    let to_bin_string payload = Data.(to_bin_string (Valid (V5 payload)))
  end
end

module Make (Serde : Serde.S) (Io : Io.S) = struct
  module Io = Io

  type payload = Serde.payload
  type t = { io : Io.t; mutable payload : payload }

  let write io payload =
    let s = Serde.to_bin_string payload in
    (* The data must fit inside a single page for atomic updates of the file.
       This is only true for some file systems. This system will have to be
       reworked for [V4]. *)
    assert (String.length s <= Io.page_size);

    Io.write_string io ~off:Int63.zero s

  let read io =
    let open Result_syntax in
    let* string = Io.read_all_to_string io in
    (* Since the control file is expected to fit in a page,
       [read_all_to_string] should be atomic for most filesystems. *)
    Serde.of_bin_string string

  let create_rw ~path ~overwrite (payload : payload) =
    let open Result_syntax in
    let* io = Io.create ~path ~overwrite in
    let+ () = write io payload in
    { io; payload }

  let open_ ~path ~readonly =
    let open Result_syntax in
    let* io = Io.open_ ~path ~readonly in
    let+ payload = read io in
    { io; payload }

  let close t = Io.close t.io
  let readonly t = Io.readonly t.io
  let payload t = t.payload

  let reload t =
    let open Result_syntax in
    if not @@ Io.readonly t.io then Error `Rw_not_allowed
    else
      let+ payload = read t.io in
      t.payload <- payload

  let read_payload ~path =
    let open Result_syntax in
    let* t = open_ ~path ~readonly:true in
    let payload = payload t in
    let+ () = close t in
    payload

  let set_payload t payload =
    let open Result_syntax in
    let+ () = write t.io payload in
    t.payload <- payload

  let fsync t = Io.fsync t.io
end

module Upper = Make (Serde.Upper)
module Volume = Make (Serde.Volume)
