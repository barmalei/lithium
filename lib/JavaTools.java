package lithium;


import java.lang.reflect.Field;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.lang.reflect.Method;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import java.util.regex.Pattern;

import java.net.URL;

import org.apache.commons.lang3.builder.ReflectionToStringBuilder;
import org.apache.commons.lang3.builder.ToStringStyle;

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

    private static final String test = "dshajdshjdahsd";

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

        List<Map> items = new ArrayList();
        for (Method method : clazz.getMethods()) {
            Map item = new HashMap();
            item.put("name", method.getName());

            String methodString = method.toGenericString();
            methodString = methodString.replaceAll(pkg, "");
            methodString = methodString.replaceAll("java.lang.", "");

            Matcher mt = pattern.matcher(methodString);
            if (mt.find()) {
                methodString = methodString.substring(0, mt.start(1)) +
                               methodString.substring(mt.end(1) + 1);
            }

            item.put("method", methodString);
            items.add(item);
        }

        Collections.<Map>sort(items, (a, b) -> {
            String n1 = (String)a.get("name");
            String n2 = (String)b.get("name");
            return n1.compareTo(n2);
        });

        for (Map item : items) {
            System.out.println("{" + item.get("method") + "}");
        }
    }

    public static String detectClassSource(String cn) throws Exception {
        Class clazz = null;
        if (cn.indexOf('.') < 0) {
            List<Class> res = classByShortName(cn);
            if (res != null && res.size() > 0) {
                if (res.size() == 1) {
                    clazz = res.get(0);
                } else {
                    System.out.println("Class '" + cn + "' cannot be resolved unambiguously");
                }
            }
        } else {
            clazz = Class.forName(cn);
        }

        if (clazz != null) {
            URL    location = clazz.getResource('/' + clazz.getName().replace('.', '/') + ".class");
            String path     = location.getPath();
            int    index    = path.indexOf('!');
            if (index > 0) {
                path = path.substring(0, index);
            }

            String pref = "file:";
            if (path.startsWith(pref)) {
                path = path.substring(pref.length());
            }

            return path;
        } else {
            return null;
        }
    }

    public static void detectFieldValue(String path) throws Exception {
        int     index = path.lastIndexOf('.') ;
        String  cn    = path.substring(0, index);
        String  fn    = path.substring(index + 1);
        Class   clazz = Class.forName(cn);
        //Field[] flds  = clazz.getDeclaredFields();

        Field  field = clazz.getField(fn);
        Object value = field.get(null);
        System.out.println("{{{" +  ReflectionToStringBuilder.toString(value, ToStringStyle.MULTI_LINE_STYLE) + "}}}");

        // for (Field field : flds) {
        //     System.out.println(" + ", " + field.get(null));
        // }
    }

    public static void main(String[] args) throws Exception {
        String info = "<methods:className> or <class:className> or <module:className> commands are expected";

        // detectConstantValue("lithium.JavaTools");
        // // TODO: removeme
        // if (args.length == 0) return;

        if (args.length == 0 || args[0].trim().length() == 0) {
            System.err.println("No argument has been passed");
            System.err.println(info);
            System.exit(1);
        }

        String command = args[0].trim();
        if (!command.startsWith("methods:") && !command.startsWith("class:") && !command.startsWith("module:") && !command.startsWith("field:")) {
            System.err.println("Unknown command: '" + command + "'");
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
        } else if ("module".equals(prefix)) {
            String path = detectClassSource(suffix);
            if (path != null) {
                System.out.println("[" + path + " => " + suffix + "]");
            }
        } else if ("field".equals(prefix)) {
            detectFieldValue(suffix);
        } else {
            System.err.println("Unknown command: '" + command + "'");
            System.err.println(info);
            System.exit(1);
        }
    }
}
