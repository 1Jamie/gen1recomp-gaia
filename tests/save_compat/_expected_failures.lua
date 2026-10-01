local GS = { "^g2%.gold%.", "^g2%.silver%." }

return {
  { id = "G1-23", check = "r1", case = "^g1%.red%.box_index_invalid$", key = "^export$",
    why = "permanent: the source cart is invalid on purpose (wCurrentBoxNum 12) and the exporter refuses it (Compat gate)" },
}
