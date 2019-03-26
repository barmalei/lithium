require 'pathname'
require 'lithium/core'
require "test/unit"

class TestCore < Test::Unit::TestCase
    def test_artifact_name
        nn = "compile:test/test/a"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/test/a", aa.path)
        assert_equal("compile:",    aa.prefix)
        assert_equal("test/test/a", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "compile:test/test/a/"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/test/a", aa.path)
        assert_equal("compile:",    aa.prefix)
        assert_equal("test/test/a/", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "compile:"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal(nil, aa.path)
        assert_equal("compile:",    aa.prefix)
        assert_equal(nil, aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH, aa.mask_type)

        nn = "test/test/a"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/test/a", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "test/test/a/"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/test/a/", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "test/../test/a"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/../test/a", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "."
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal(".", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal(".", aa.suffix)
        assert_equal(nil, aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "test/../test/a/*.java"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/../test/a/*.java", aa.suffix)
        assert_equal("*.java", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "test/../test/a/**/*.java"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/../test/a/**/*.java", aa.suffix)
        assert_equal("**/*.java", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "test/../test/a/*"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/a", aa.path)
        assert_equal(nil, aa.prefix)
        assert_equal("test/../test/a/*", aa.suffix)
        assert_equal("*", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "aaa:bbb:test/../test/a/*"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("test/a", aa.path)
        assert_equal("aaa:", aa.prefix)
        assert_equal("bbb:test/../test/a/*", aa.suffix)
        assert_equal("*", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)

        nn = "aaa:*"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal(nil, aa.path)
        assert_equal("aaa:", aa.prefix)
        assert_equal("*", aa.suffix)
        assert_equal("*", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH, aa.mask_type)

        nn = "aaa:a/*/*"
        aa = ArtifactName.new(nn)
        assert_equal(nn, aa.to_s)
        assert_equal("a", aa.path)
        assert_equal("aaa:", aa.prefix)
        assert_equal("*/*", aa.path_mask)
        assert_equal(File::FNM_DOTMATCH | File::FNM_PATHNAME, aa.mask_type)
    end

    def test_artifact
        aa = Artifact.new("test")
        assert_equal(aa.name, "test")
        assert_equal(aa.to_s, aa.shortname)
        assert_equal(aa.shortname, "test")
        assert_nil(aa.owner)
        assert_equal(aa.homedir, Dir.pwd)
        assert_equal(aa.requires, [])
        assert_true(aa.expired?)
        assert_equal(aa.mtime, -1)

        aa.REQUIRE("test1", "test2")
        assert_equal(aa.requires, [ "test1", "test2" ])
    end

    def test_
    end

    def test_artname_sort()
        for i in 1..10 do
            arts = [
                ArtifactName.new("compile:test/test/a"),
                ArtifactName.new("compile:"),

                ArtifactName.new("aa:test/test/b"),
                ArtifactName.new("aa:test/test/b/c"),
                ArtifactName.new("aa:test/test/*"),
                ArtifactName.new("aa:test/test/a"),
                ArtifactName.new("aa:test/*/*"),
                ArtifactName.new("aa:test/"),
                ArtifactName.new("aa:"),

                ArtifactName.new("test/test/b"),
                ArtifactName.new("test/test/b/c"),
                ArtifactName.new("test/test/*"),
                ArtifactName.new("test/test/a"),
                ArtifactName.new("test/*/*"),
                ArtifactName.new("test/"),

                ArtifactName.new("compile:test/**/*"),
                ArtifactName.new("bb:")
            ]

            arts = arts.sort

            assert_equal(arts[0], "aa:test/test/a")
            assert_equal(arts[1], "aa:test/test/b")
            assert_equal(arts[2], "aa:test/test/*")
            assert_equal(arts[3], "aa:test/*/*")
            assert_equal(arts[4], "aa:test/")
            assert_equal(arts[5], "aa:test/test/b/c")
            assert_equal(arts[6], "aa:")
            assert_equal(arts[7], "bb:")

            assert_equal(arts[8], "compile:test/test/a")
            assert_equal(arts[9], "compile:test/**/*")
            assert_equal(arts[10],"compile:")
            assert_equal(arts[11], "test/test/*")
            assert_equal(arts[12], "test/*/*")
            assert_equal(arts[13], "test/")
            assert_equal(arts[14], "test/test/a")
            assert_equal(arts[15], "test/test/b")
            assert_equal(arts[16], "test/test/b/c")
            arts = arts.shuffle
        end
    end

    def test_fileartifact()
        pw = Dir.pwd

        fa = FileArtifact.new("test/a")
        assert_equal(fa.name, "test/a")
        assert_equal(fa.homedir, pw)
        assert_equal(fa.fullpath, File.join(pw, fa.name))
        assert_equal(fa.fullpath("b"), File.join(pw, "b"))
        assert_false(fa.is_absolute)
        assert_false(fa.is_permanent)
        assert_equal(fa.mtime, -1)
        assert_false(fa.match("a"))
        assert_false(fa.match("test/a"))

        fa = FileArtifact.new("/test/a")
        assert_equal(fa.name, "/test/a")
        assert_equal(fa.homedir, "/test")
        assert_equal(fa.fullpath, fa.name)
        assert_equal(fa.fullpath("b"), "/test/b")
        assert_true(fa.is_absolute)
        assert_false(fa.is_permanent)
        assert_equal(fa.mtime, -1)
        assert_false(fa.match("a"))
        assert_false(fa.match("test/a"))
        assert_true(fa.match("/test"))
        assert_false(fa.match("/test2"))
        assert_false(fa.match("/test22222"))
        assert_true(fa.match("/test/**/*"))
        assert_true(fa.match("/test/*"))
        assert_true(fa.match("/test/a"))
        assert_true(fa.match("/test/a/*"))
        assert_false(fa.match("/test2/a/*"))
    end

    def test_project()
        pw  = Dir.pwd

        prj = Project.new(pw)
        assert_true(prj.match(File.join(pw, 'test')))
        assert_equal(prj.homedir, pw)
        assert_equal(prj.fullpath, pw)
        assert_equal(prj.fullpath, prj.homedir)
        assert_nil(prj.owner)
        assert_equal(prj.top, prj)
        assert_nil(prj.find_meta("abc"));

        prj.ARTIFACT("a/b/c", FileArtifact)
        mm = prj.find_meta("a/b/c")
        assert_not_nil(mm);
        assert_equal(mm.artname, "a/b/c")
        assert_equal(mm[:clazz], FileArtifact)
        assert_nil(mm[:block])
        assert_nil(mm[:def_value])

        aa = prj.artifact("a/b/c")
        assert_not_nil(aa)
        assert_equal(prj._artifact_from_cache(aa.name, prj.find_meta(aa.name)), aa)
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "a/b/c")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/b/c"))
        assert_equal(aa.homedir, prj.homedir)

        aa = prj.artifact("FileArtifact:a/b/k")
        assert_equal(aa.name, "a/b/k")
        key = "FileArtifact:" + aa.name
        assert_equal(prj._artifact_from_cache(key, prj.find_meta(key)), aa)
        assert_nil(prj.find_meta("a/b/k"))
        assert_nil(prj.find_meta("FileArtifact:a/b/k"))
        assert_not_nil(aa)
        assert_equal(aa.name, "a/b/k")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/b/k"))
        assert_equal(aa.homedir, prj.homedir)

        aa = prj.artifact("FileArtifact:a/b/k") {
            puts "!!!!!!!!!!!!!!!!!!!!!! #{self}"
            @test = 100
        }
        assert_nil(prj.find_meta("a/b/k"))
        assert_nil(prj.find_meta("FileArtifact:a/b/k"))
        key = "FileArtifact:" + aa.name
        assert_equal(prj._artifact_from_cache(key, nil), aa)
        assert_not_nil(aa)
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "a/b/k")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/b/k"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 100)

        prj.ARTIFACT("a/**/*", FileArtifact) { @test = 200 }
        prj.ARTIFACT("*", FileArtifact) { @test = 300 }
        prj.ARTIFACT("a/b/*", FileArtifact) { @test = 400 }

        aa = prj.artifact("a/b/y")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new(aa.name)])
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "a/b/y")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/b/y"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 400)

        aa = prj.artifact("a/y/y")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new(aa.name)])
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "a/y/y")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/y/y"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 200)

        aa = prj.artifact("a/yy/y")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new(aa.name)])
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "a/yy/y")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "a/yy/y"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 200)

        aa = prj.artifact("b")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new(aa.name)])
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "b")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "b"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 300)

        prj.ARTIFACT("*", FileArtifact) {
            @test = 1000
        }

        aa = prj.artifact("b")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new(aa.name)])
        assert_true(aa.kind_of?(FileArtifact))
        assert_equal(aa.name, "b")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "b"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 1000)

        prj.ARTIFACT("action:", '.', FileMask) {
            @test = 2000
        }

        prj.ARTIFACT("action:test", FileArtifact) {
            @test = 3000
        }

        prj.ARTIFACT("action:test/*", FileCommand) {
            @test = 4000
        }

        aa = prj.artifact("action:")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new("action:" + aa.name)])
        assert_true(aa.class == FileMask)
        assert_equal(aa.name, ".")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, pw)
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 2000)

        aa = prj.artifact("action:test")
        assert_not_nil(aa)
        assert_not_nil(prj._artifacts[ArtifactName.new("action:" + aa.name)])
        assert_true(aa.class == FileArtifact)
        assert_equal(aa.name, "test")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "test"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 3000)

        aa = prj.artifact("action:test/aa")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new("action:" + aa.name)])
        assert_true(aa.class == FileCommand)
        assert_equal(aa.name, "test/aa")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "test/aa"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 4000)

        aa = prj.artifact("action:test/*.java")
        assert_not_nil(aa)
        assert_nil(prj._artifacts[ArtifactName.new("action:" + aa.name)])
        assert_true(aa.class == FileCommand)
        assert_equal(aa.name, "test/*.java")
        assert_equal(aa.owner, prj)
        assert_equal(aa.fullpath, File.join(pw, "test/*.java"))
        assert_equal(aa.homedir, prj.homedir)
        assert_equal(aa.instance_variable_get("@test"), 4000)

        art  = Artifact.new("aaa")
        fart = FileArtifact.new(pw)
        prj1 = Project.new(pw)
        prj2 = Project.new(pw)
        assert_true(prj1 == prj2)
        assert_false(prj1 == fart)
        assert_false(prj2 == fart)
        assert_false(prj1 == art)
        assert_false(prj2 == art)
        assert_false(fart == art)

        prj1.ARTIFACT(FileArtifact)
        assert_false(prj1 == prj2)

        prj2.ARTIFACT(FileArtifact)
        assert_true(prj1 == prj2)

        prj1.ARTIFACT("test:*", Project) {
            ARTIFACT("s", FileArtifact)
        }

        assert_false(prj1 == prj2)
        prj11 = prj1.artifact("test:s")

    #assert_false(prj1 == )

    end

    def test_filecommand_artifact()
        aa = FileCommand.new("test/test")
        assert_equal(aa.class, FileCommand)
        assert_equal(aa.name, "test/test")
        assert_equal(aa.fullpath, File.join(Dir.pwd, "test/test"))
        assert_true(aa.expired?)
    end

    def test_artname_match()
        aa = ArtifactName.new("compile:test/test/a")
        assert_true(aa.match("compile:test/test/a"))
        assert_false(aa.match("compile:test/test/a/a"))
        assert_false(aa.match("compile:test/test/a/*"))
        assert_false(aa.match("compile:test/*"))
        assert_false(aa.match("compile:test/**/*"))
        assert_false(aa.match("compile:"))
        assert_false(aa.match("test/test/a"))

        aa = ArtifactName.new("compile:")
        assert_true(aa.match("compile:"))
        assert_false(aa.match("compile:test/test/a/a"))
        assert_false(aa.match("compile:test/test/a/*"))
        assert_false(aa.match("compile:test/*"))
        assert_false(aa.match("compile:test/**/*"))
        assert_false(aa.match("test/test/a"))

        aa = ArtifactName.new("compile:*")
        assert_false(aa.match("compile:"))
        assert_true(aa.match("compile:test/test/a/a"))
        assert_true(aa.match("compile:test/test/a/*"))
        assert_true(aa.match("compile:test/*"))
        assert_true(aa.match("compile:test/**/*"))
        assert_false(aa.match("test/test/a"))

        aa = ArtifactName.new("compile:a/*")
        assert_false(aa.match("compile:"))
        assert_true(aa.match("compile:a/a"))
        assert_true(aa.match("compile:a/b"))
        assert_true(aa.match("compile:a/*"))
        assert_false(aa.match("compile:a/a/b"))
        assert_false(aa.match("compile:test/**/*"))
        assert_false(aa.match("a/a"))

        aa = ArtifactName.new("a/*")
        assert_false(aa.match("a"))
        assert_true(aa.match("a/a"))
        assert_true(aa.match("a/b"))
        assert_true(aa.match("a/*"))
        assert_false(aa.match("a/a/b"))
        assert_false(aa.match("test/**/*"))
        assert_false(aa.match("b/a"))

        aa = ArtifactName.new("a/*/*")
        assert_false(aa.match("a"))
        assert_false(aa.match("a/a"))
        assert_false(aa.match("a/b"))
        assert_false(aa.match("a/*"))
        assert_true(aa.match("a/a/b"))
        assert_true(aa.match("a/a/*"))
        assert_true(aa.match("a/*/*"))
        assert_true(aa.match("a/*/a"))
        assert_false(aa.match("a/*/a/a"))
        assert_false(aa.match("a/*/*/a"))
    end

    def test_artifact_meta
        nn = FileArtifact
        aa = ArtifactMeta.new(nn)
        assert_equal(nn,  aa[:clazz])
        assert_equal("FileArtifact",  aa.artname.to_s)
        assert_nil(aa[:def_value])
        assert_nil(aa[:block])
        assert_nil(aa[:clean])

        nn = 'FileArtifact:'
        aa = ArtifactMeta.new(nn)
        assert_equal(FileArtifact,  aa[:clazz])
        assert_equal("FileArtifact:",  aa.artname.prefix)
        assert_nil(aa[:def_value])
        assert_nil(aa[:block])
        assert_nil(aa[:clean])

        nn = 'test:test/com'
        aa = ArtifactMeta.new(nn, FileArtifact) {}
        assert_equal(FileArtifact,  aa[:clazz])
        assert_equal(nn,  aa.artname)
        assert_nil(aa[:def_value])
        assert_not_nil(aa[:block])
        assert_nil(aa[:clean])

        nn = 'FileArtifact:test/com'
        aa = ArtifactMeta.new(nn) {}
        assert_equal(FileArtifact,  aa[:clazz])
        assert_equal(nn,  aa.artname)
        assert_nil(aa[:def_value])
        assert_not_nil(aa[:block])
        assert_nil(aa[:clean])

        mm1 = ArtifactMeta.new(nn) {}
        mm2 = ArtifactMeta.new(nn)
        assert_false(mm1 == mm2)

        mm1 = ArtifactMeta.new(nn)
        mm2 = ArtifactMeta.new(nn)
        assert_true(mm1 == mm2)

        mm1 = ArtifactMeta.new(FileArtifact)
        mm2 = ArtifactMeta.new(Directory)
        assert_false(mm1 == mm2)
    end
end





