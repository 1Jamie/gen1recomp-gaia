local Common = require("tests.drivers.battle_move_swap_common")

return function(game)
  Common.run(game, {
    version = "emerald",
    tag = "em",
    dir = "/tmp/em_battle_move_swap",
    newGame = { action = "new_game", name = "NICK", gender = 0 },
  })
end
