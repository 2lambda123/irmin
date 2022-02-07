open Util

(** Interface provided by a suffix file; file-like, except that we take account of the
    suffix offset *)
module type S = sig
  type t
  val create: root:string -> suffix_offset:int -> t
  val open_: root:string -> t
  val close: t -> unit
  val fsync: t -> unit

  val size : t -> int
  (** Return the virtual size: the size of the underlying data file, plus the offset *)

  val pread: t -> off:int ref -> len:int -> buf:bytes -> int
  (** [pread t ~off ~len ~buf] reads len bytes of data from the data file at [(off -
      suffix_offset)]; [off] is updated; file seek pointer is altered as a side effect.

      Requires off >= suffix_offset; requires |buf|>= len; always reads the required
      number of bytes, unless there are not that many bytes in the file; returns the
      number of bytes actually read *)

  val pwrite: t -> off:int ref -> bytes -> unit
  (** [pwrite t ~off buf] writes the bytes into the data file at offset [off -
      suffix_offset]; [off] is updated; file seek pointer altered as a side effect.

      Requires off >= suffix_offset. 
  *)

  val append: t -> string -> unit
end

module Private = struct
  type t = { data: Unix.file_descr; suffix_offset: int }

  let data_name = "suffix_data"
  let offset_name = "suffix_offset"

  module Offset_file = struct
    module T = struct
      open Sexplib.Std
      type t = { suffix_offset: int }[@@deriving sexp]
    end
    include T
    include Add_load_save_funs(T)
  end

  let create ~root ~suffix_offset = 
    let ok = not (Sys.file_exists root) in
    assert(ok);
    mkdir ~path:root;
    let data = File.create ~path:Fn.(root / data_name) in    
    Offset_file.(save {suffix_offset} Fn.(root / offset_name));
    { data; suffix_offset }

  let open_ ~root = 
    let ok = 
      Sys.file_exists root 
      && Sys.file_exists Fn.(root / data_name)
      && Sys.file_exists Fn.(root / offset_name)
    in
    assert(ok);
    let data = File.open_ ~path:Fn.(root / data_name) in
    let suffix_offset = 
      Offset_file.load Fn.(root / offset_name) |> fun x -> x.suffix_offset
    in
    { data; suffix_offset }

  let close t = Unix.close t.data

  let fsync t = Unix.fsync t.data

  let size t = (Unix.fstat t.data).st_size + t.suffix_offset
                                               
  let pread t ~off ~len ~buf = 
    assert(!off >= t.suffix_offset);
    let n = File.pread t.data ~off:(ref (!off - t.suffix_offset)) ~len ~buf in
    off:=!off + n;
    n

  let pwrite t ~off buf =
    assert(!off >= t.suffix_offset);
    File.pwrite t.data ~off:(ref (!off - t.suffix_offset)) buf;
    off:=!off + Bytes.length buf;
    ()

  let append t s = pwrite t ~off:(ref (size t)) (Bytes.unsafe_of_string s)
end


include (Private : S)