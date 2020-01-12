package lithium;

import java.util.List;
import java.util.ArrayList;

public class DiscoverSystemClass {
    private static final String[] packages = new String[] {
        "java.util",
        "java.util.function",
        "java.util.regex",
        "java.util.concurrent",
        "java.util.concurrent.atomic",
        "java.util.stream",
        "javax.crypto",
        "java.io",
        "java.text",
        "java.nio",
        "java.nio.file",
        "java.lang.reflect",
        "java.math",
        "java.net",
        "java.time",
        "java.sql",
        "java.security"
    };

    public static List<Class> classByShortName(String name) throws Exception {
        List<Class> res = new ArrayList();
        for (String pkg :  packages) {
            try {
                String fullClassName = String.format("%s.%s", pkg, name);
                Class clz = Class.forName(fullClassName);
                res.add(clz);
            } catch (Exception e) {

            }
        }
        return res;
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0 || args[0].trim().length() == 0) {
            System.err.println("No class name has bee passed as an argument");
            System.exit(1);
        }

        int    count  = 0;
        String suffix = ".class";
        String clname = args[0].trim();
        if (clname.endsWith(suffix)) {
            clname = clname.substring(0, clname.length() - suffix.length());
        }

        for (Class clazz : classByShortName(clname)) {
            count++;
            System.out.println("[JAVA/rt.jar => " + clazz.getName() + "]");
        }
    }
}