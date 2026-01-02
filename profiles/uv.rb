-> {
    REQUIRE UvLockFile
    UvRun("run:**/src/**/*.py")
    UvRunBlackTool("compile:**/*.py")
    UvRunTest("run:**/test/**/*.py")
    UvRunTest("run:**/tests/**/*.py")
}