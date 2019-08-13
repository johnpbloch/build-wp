workflow "Build Periodically" {
  on = "schedule(*/15 * * * *)"
  resolves = ["docker://johnpbloch/build-wp:latest"]
}

action "docker://johnpbloch/build-wp:latest" {
  uses = "docker://johnpbloch/build-wp:latest"
  env = {
    VCS_AUTH_USER = "johnpbloch-bot"
  }
  secrets = ["VCS_AUTH_PW"]
}
