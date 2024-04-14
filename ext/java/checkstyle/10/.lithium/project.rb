-> {
    # REQUIRE {
    #     MavenDependenciesDir(".") {
    #          TRANSITIVE(false)
    #      }
    #  }

    REQUIRE {
       HttpRemoteFile("checkstyle-10.15.0-all.jar") {
           @uri = "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-10.15.0/checkstyle-10.15.0-all.jar"
       }
    }
}
