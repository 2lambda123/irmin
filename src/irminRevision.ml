(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
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

module type S = sig
  include IrminValue.S
  val create: ?tree:key -> key list -> t
  val tree: t -> key option
  val parents: t -> key list
end

module Make (K: IrminKey.S) = struct

  type key = K.t

  type t = {
    tree   : key option;
    parents: key list;
  }

  let key t =
    let keys = match t.tree with
      | None   -> t.parents
      | Some k -> k :: t.parents in
    K.concat keys

  let parents t = t.parents

  let tree t = t.tree

  let create ?tree parents =
    { tree; parents }

  module XTree = struct
    include IrminBase.Option(K)
    let name = "tree"
  end
  module XParents = struct
    include IrminBase.List(K)
    let name = "parents"
  end
  module XRevision = struct
    include IrminBase.Pair(XTree)(XParents)
    let name = "revision"
  end

  let name = XRevision.name

  let set buf t =
    XRevision.set buf (t.tree, t.parents)

  let get buf =
    let tree, parents = XRevision.get buf in
    { tree; parents }

  let sizeof t =
    XRevision.sizeof (t.tree, t.parents)

  let to_json t =
    XRevision.to_json (t.tree, t.parents)

  let of_json j =
    let tree, parents = XRevision.of_json j in
    { tree; parents }

  let dump t =
    XRevision.dump (t.tree, t.parents)

  let pretty t =
    XRevision.pretty (t.tree, t.parents)

  let hash t =
    XRevision.hash (t.tree, t.parents)

  let compare t1 t2 =
    XRevision.compare (t1.tree, t1.parents) (t2.tree, t2.parents)

  let equal t1 t2 =
    compare t1 t2 = 0

end

module Simple = Make(IrminKey.SHA1)
