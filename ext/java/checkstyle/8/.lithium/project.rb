-> {
    # REQUIRE {
    #     MavenDependenciesDir(".") {
    #         TRANSITIVE(false)
    #     }
    # }

    REQUIRE {
        HttpRemoteFile("checkstyle-8.45.1-all.jar") {
            @uri = "https://github.com/checkstyle/checkstyle/releases/download/checkstyle-8.45.1/checkstyle-8.45.1-all.jar"
        }
    }
}