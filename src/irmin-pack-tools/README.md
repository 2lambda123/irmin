# Irmin-pack-tools
This folder contains several tools meant to provide usefull ways to debug and dump informations about stores.

Currently, there are the following tools:
- [`ppcf`](#ppcf), a json printer for control files
- [`ppidx`](#ppidx), a json printer for index folders
- [`tezos-explorer`](#tezos-explorer), a gui for a fast exploration of tezos stores

## ppcf
This tool prints a control file in a human readable manner (json), allowing to fetch important informations easily.
It is fairly straightforward:
```shell
$ dune exec -- irmin-ppcf Upper|Volume <path-to-control-file>
```
The first argument, either `Upper` or `Volume` tells the tool if you are trying to read the control file of a normal store, or from a volume store.
The second one is the path to the control file (e.g. `output/root/store.control`)

It will typically give the following json output:
```
{"Valid":{"V5":{"dict_end_poff":1548250,"appendable_chunk_poff":9056699,"checksum":2724660738,"chunk_start_idx":1,"chunk_num":5,"volume_num":0,"status":{"Gced":{"suffix_start_offset":35654891,"generation":5,"latest_gc_target_offset":35654787,"suffix_dead_bytes":20655801}}}}}
```
Which can be further improved using the tool `jq`:
```shell
$ dune exec -- irmin-ppcf Upper|Volume <path-to-control-file> | jq
```
Will give:
```json
{
  "Valid": {
    "V5": {
      "dict_end_poff": 1548250,
      "appendable_chunk_poff": 9056699,
      "checksum": 2724660738,
      "chunk_start_idx": 1,
      "chunk_num": 5,
      "volume_num": 0,
      "status": {
        "Gced": {
          "suffix_start_offset": 35654891,
          "generation": 5,
          "latest_gc_target_offset": 35654787,
          "suffix_dead_bytes": 20655801
        }
      }
    }
  }
}
```

## ppidx
This tool prints the informations stored in the index of a store in a human readable manner (json), allowing to fetch important informations easily.
It is fairly straightforward:
```shell
$ dune exec -- irmin-ppidx <path-to-store>
```
The second one is the path to the root of the store, not the index folder (e.g. `output/root/` where `output/root/index/` exists)

It will typically give the following json output, with one line per entry registered:
```
{"hash":"cGrDVlQkzEjlw2DA4bL5fAnDSOh4TRKtLZrAiavclsI=","off":13431448,"len":101,"kind":"Commit_v2"}
{"hash":"i2LiUbc7fPMu5ON1MLN97thf7cU0OUTcDBwNlvzAUVo=","off":95461096,"len":103,"kind":"Commit_v2"}
{"hash":"cXMN2n8Re6RAvVbHbzaptzfIdFp+X/ey36S5RiWTsUw=","off":28541134,"len":104,"kind":"Commit_v2"}
...
```
Which can be further improved using the tool `jq`:
```shell
$ dune exec -- irmin-ppidx <path-to-store> > index
$ jq -s '.' -- index
```
Will give:
```json
{
  "hash": "cGrDVlQkzEjlw2DA4bL5fAnDSOh4TRKtLZrAiavclsI=",
  "off": 13431448,
  "len": 101,
  "kind": "Commit_v2"
}
{
  "hash": "i2LiUbc7fPMu5ON1MLN97thf7cU0OUTcDBwNlvzAUVo=",
  "off": 95461096,
  "len": 103,
  "kind": "Commit_v2"
}
{
  "hash": "cXMN2n8Re6RAvVbHbzaptzfIdFp+X/ey36S5RiWTsUw=",
  "off": 28541134,
  "len": 104,
  "kind": "Commit_v2"
}
...
```

However, it might be useful to sort the json output using the offset. You can do so by specifying a sort function:
```shell
$ jq -s 'sort_by(.off)' -- index
```

## tezos-explorer
TODO
