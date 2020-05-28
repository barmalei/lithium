package lithium;

import java.lang.Class;
import java.lang.reflect.Method;
import java.util.ArrayList;

import java.util.List;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class JavaTools {
    private static final String[] packages = new String[] {
        "java.util",
        "java.util.function",
        "java.util.regex",
        "java.util.concurrent",
        "java.util.concurrent.atomic",
        "java.util.concurrent.locks",
        "java.util.stream",
        "java.io",
        "java.text",
        "java.nio",
        "java.nio.file",
        "java.lang",
        "java.lang.reflect",
        "java.math",
        "java.net",
        "java.time",
        "java.time.format",
        "java.sql",
        "java.security",
        "javax.crypto"
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

    public static void printMethods(Class clazz) throws Exception {
        String  pkg     = clazz.getPackage().getName() + ".";
        Pattern pattern = Pattern.compile(" ([^ ]+)(\\.[a-zA-Z_][a-zA-Z0-9_]*)\\(");

        for (Method method : clazz.getMethods()) {
            String methodString = method.toGenericString();
            methodString = methodString.replaceAll(pkg, "");
            methodString = methodString.replaceAll("java.lang.", "");

            Matcher mt = pattern.matcher(methodString);
            if (mt.find()) {
                methodString = methodString.substring(0, mt.start(1)) +
                               methodString.substring(mt.end(1) + 1);
            }
            System.out.println("{" + methodString + "}");
        }
    }

    public static void main(String[] args) throws Exception {
        String info = "<methods:className> or <class:className> commands are expected";

        if (args.length == 0 || args[0].trim().length() == 0) {
            System.err.println("No argument has been passed");
            System.err.println(info);
            System.exit(1);
        }

        String command = args[0].trim();
        if (!command.startsWith("methods:") && !command.startsWith("class:")) {
            System.err.println("Unknown command");
            System.err.println(info);
            System.exit(1);
        }

        String prefix = command.substring(0, command.indexOf(':')).trim();
        String suffix = command.substring(command.indexOf(':') + 1).trim();

        if ("class".equals(prefix)) {
            String extension = ".class";
            if (suffix.endsWith(extension)) {
                suffix = suffix.substring(0, suffix.length() - extension.length());
            }

            for (Class clazz : classByShortName(suffix)) {
                System.out.println("[JAVA/rt.jar => " + clazz.getName() + "]");
            }
        } else if ("methods".equals(prefix)) {
            Class clazz = null;
            try {
                System.out.println("JavaTools.main(): Class.forName(" + suffix + ")");
                clazz = Class.forName(suffix);
            } catch (ClassNotFoundException e) {

                if (args.length > 1 && suffix.indexOf('.') <= 0) {
                    String pkg_name = args[1].trim();
                    System.out.println("JavaTools.main(): Class.forName(" + pkg_name + "." + suffix + ")");
                    try {
                        clazz = Class.forName(pkg_name + "." + suffix);
                    } catch (ClassNotFoundException ee) { }
                }

                if (clazz == null) {
                    System.out.println("JavaTools.main(): classByShortName(" + suffix + ")");
                    List<Class> classes = classByShortName(suffix);
                    System.out.println(classes);
                    if (classes.size() == 1) {
                        clazz = classes.get(0);
                    } else {
                        System.err.println("Class '" + suffix + "' cannot be found");
                        System.exit(1);
                    }
                }
            }

            printMethods(clazz);
        } else {
            System.err.println("Unknown command");
            System.err.println(info);
            System.exit(1);
        }
    }
}
