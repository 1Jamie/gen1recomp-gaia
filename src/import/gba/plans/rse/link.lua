return {
  tasks = {
    {
      id = "rse_link",
      run = "steps",
      weight = 0.01,
      steps = {
        { name = "src.import.gba.rse.link_extract", label = "Link Trade" },
      },
    },
  },
  sequential = { "rse_link" },
  dirs = { "/trade" },
}
