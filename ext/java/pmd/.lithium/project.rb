-> {
    REQUIRE {
        HttpRemoteFile("pmd-dist-7.0.0-bin.zip") {
            @uri = "https://github.com/pmd/pmd/releases/download/pmd_releases%2F7.0.0/pmd-dist-7.0.0-bin.zip"
        }

        UnzipDirectory("./") {
            @source = 'pmd-dist-7.0.0-bin.zip'
        }

        BUILT {
            if File.directory?('pmd-bin-7.0.0')
                FileUtils.cp_r(Dir.glob('pmd-bin-7.0.0/*'), ".")
                FileUtils.rm_r('pmd-bin-7.0.0')
            end
        }
    }
}