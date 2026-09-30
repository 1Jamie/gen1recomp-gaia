local Common = require("tests.drivers.battle_move_swap_common")

return function(game)
  Common.run(game, {
    version = "firered",
    tag = "frlg",
    dir = "/tmp/game3_battle_move_swap",
    newGame = { action = "new_game", name = "RED" },
  })
end
