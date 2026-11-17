terraform {
  cloud {
    organization = "horrell"

    workspaces {
      name = "doks-runners-cluster"
    }
  }
}
