# Mod option schema export

`mod_option_schemas.json` is an optional runtime snapshot written beside
`options.lua` after the mod loader finishes. It gives a native launcher a
data-only description of mod settings without requiring the launcher to run
untrusted mod entry code before boot.

Version 1 has this shape:

```json
{
  "schema_version": 1,
  "mods": {
    "example": [
      {"key":"enabled","type":"toggle","label":"Enabled","default":true},
      {"key":"mode","type":"choice","label":"Mode","default":"safe",
       "choices":[["Safe","safe"],["Fast","fast"]]},
      {"key":"rate","type":"number","label":"Rate","default":5,
       "min":0,"max":10,"step":1},
      {"key":"name","type":"text","label":"Name","default":"","maxLen":12}
    ]
  }
}
```

Only enabled, successfully loaded mods are included. A boot with no schemas
writes `{"schema_version":1,"mods":{}}` when an older snapshot exists, so a
disabled or failed mod cannot leave stale settings rows behind. A filesystem
that cannot write is tolerated, and a fresh mod-free boot does not create the
file.

The supported row types are `toggle`, `choice`, `number`, and `text`. Native
consumers may ignore unknown future row types. Consumers must accept a
missing `schema_version` as legacy version 1 and ignore newer versions rather
than guessing at their shape. Producers must bump the version when changing
the document shape.
