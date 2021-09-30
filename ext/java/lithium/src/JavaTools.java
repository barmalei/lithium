package lithium;


import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.lang.reflect.Constructor;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Arrays;
import java.util.stream.Collectors;
import java.lang.reflect.Method;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import java.util.regex.Pattern;

import java.net.URL;

import org.apache.commons.lang3.builder.ReflectionToStringBuilder;
import org.apache.commons.lang3.builder.ToStringStyle;

import com.fasterxml.jackson.databind.ObjectMapper;

public class JavaTools {
    private static final String[] packages = new String[] {
        "java.util",
        "java.lang.annotation",
        "java.util.function",
        "java.util.regex",
        "java.util.concurrent",
        "java.util.concurrent.atomic",
        "java.util.concurrent.locks",
        "java.util.stream",
        "java.beans",
        "java.io",
        "java.text",
        "java.nio",
        "java.nio.file",
        "java.nio.channels",
        "java.lang",
        "java.lang.reflect",
        "java.math",
        "java.net",
        "java.time",
        "java.time.format",
        "java.time.temporal",
        "java.sql",
        "java.security",
        "javax.crypto"
    };

    private static final ObjectMapper MAPPER = new ObjectMapper();

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

    public static String decodeAccessModifiers(int modifiers) {
        return (modifiers & Modifier.PRIVATE)  > 0
            ? "private"
            : (modifiers & Modifier.PROTECTED)  > 0
                ? "protected"
                : (modifiers & Modifier.PUBLIC)  > 0
                    ? "public"
                    : "friendly";
    }

    public static List<String> decodeLevelsModifiers(int modifiers) {
        List<String> level = new ArrayList();
        if ((modifiers & Modifier.ABSTRACT) > 0) {
            level.add("abstract");
        }

        if ((modifiers & Modifier.FINAL) > 0) {
            level.add("final");
        }

        if ((modifiers & Modifier.STATIC) > 0) {
            level.add("static");
        }
        return level;
    }

    public static Map constructorInfo(Constructor method) throws Exception {
        Map json      = new LinkedHashMap();
        int modifiers = method.getModifiers();
        json.put("name", "constructor");
        json.put("access", decodeAccessModifiers(modifiers));
        json.put("declareIn", method.getDeclaringClass().getName());

        List<String> args = new ArrayList();
        for (Class paramType : method.getParameterTypes()) {
            args.add(paramType.getTypeName());
        }
        json.put("args", args);
        return json;
    }

    public static Map fieldInfo(Field field) throws Exception {
        Map json      = new LinkedHashMap();
        int modifiers = field.getModifiers();
        json.put("name", field.getName());
        json.put("type", field.getType().getTypeName());
        json.put("access", decodeAccessModifiers(modifiers));
        json.put("level", decodeLevelsModifiers(modifiers));
        json.put("declareIn", field.getDeclaringClass().getName());
        return json;
    }

    public static Map methodInfo(Method method) throws Exception {
        Map json      = new LinkedHashMap();
        int modifiers = method.getModifiers();
        json.put("name", method.getName());
        json.put("access", decodeAccessModifiers(modifiers));
        json.put("level", decodeLevelsModifiers(modifiers));
        json.put("declareIn", method.getDeclaringClass().getName());

        List<String> args = new ArrayList();
        for (Class paramType : method.getParameterTypes()) {
            args.add(paramType.getTypeName());
        }
        json.put("args", args);

        json.put("return", method.getReturnType().getTypeName());
        return json;
    }

    public static Map findMethodInfo(List<Map> methods, Method m2) {
        return methods.stream().filter(m1 -> {
            String       name    = (String) m1.get("name");
            String       retType = (String) m1.get("return");
            List<String> args    = (List<String>) m1.get("args");
            Class[]      params  = m2.getParameterTypes();

            boolean b = (args.size() == m2.getParameterCount() &&
                         m2.getName().equals(name) &&
                         m2.getReturnType().getTypeName().equals(retType));

            if (b) {
                for (int i = 0; i < params.length; i++) {
                    if (!args.get(i).equals(params[i].getTypeName())) {
                        return false;
                    }
                }
            }

            return b;
        }).findFirst().orElse(null);
    }

    public static Map classInfo(Class clazz) throws Exception {
        Map json = new LinkedHashMap();

        String type = clazz.isInterface() ? "interface"
                                          : clazz.isEnum() ? "enum" : "class";

        json.put("name", clazz.getName());
        json.put("type", type);
        json.put("parent", clazz.getSuperclass() != null ? clazz.getSuperclass().getName() : null );
        json.put("interfaces", Arrays.stream(clazz.getInterfaces()).map(e -> e.getName()).collect(Collectors.toList()));

        List<Map>    methods      = new ArrayList();
        List<Map>    constructors = new ArrayList();
        List<Map>    fields       = new ArrayList();
        List<Class>  classes      = new ArrayList();

        classes.add(clazz);
        if (clazz.getSuperclass() != null) {
            classes.add(clazz.getSuperclass());
        }

        for (Class clz : classes) {
            for (Constructor constr : clz.getConstructors()) {
                Map ci = constructorInfo(constr);
                ci.put("declareHere", constr.getDeclaringClass() == clazz);
                constructors.add(ci);
            }

            for (Method method : clz.getDeclaredMethods()) {
                Map prevMi = findMethodInfo(methods, method);
                if (prevMi == null) {
                    Map mi = methodInfo(method);
                    mi.put("declareHere", method.getDeclaringClass() == clazz);
                    methods.add(mi);
                }
            }

            for (Field field : clz.getDeclaredFields()) {
                Map fi = fieldInfo(field);
                fi.put("declareHere", field.getDeclaringClass() == clazz);
                fields.add(fi);
            }
        }

        json.put("fields", fields);
        json.put("methods", methods);
        json.put("constructors", constructors);
        return json;
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
        //Field[] flds  = clazz.getDeclaredFields();

        Class clazz = null;
        while (true) {
            try {
                clazz = Class.forName(cn);
                break;
            } catch (ClassNotFoundException e) {
                index = cn.lastIndexOf('.');
                if (index <= 0) {
                    break;
                } else {
                    cn = cn.substring(0, index) + "$" + cn.substring(index + 1);
                }
            }
        }

        if (clazz == null) {
            throw new RuntimeException("Class cannot be identified by cn = '" + cn + "'");
        }

        Field  field = clazz.getDeclaredField(fn);
        field.setAccessible(true);
        Object value = field.get(null);
        System.out.println("{{{" +  ReflectionToStringBuilder.toString(value, ToStringStyle.MULTI_LINE_STYLE) + "}}}");

        // for (Field field : flds) {
        //     System.out.println(" + ", " + field.get(null));
        // }
    }

    public static void main(String[] args) throws Exception {
        // int k = 0;
        // if (k == 0) {
        //     System.out.println(List.class.getMethod("get", new Class[] { Integer.TYPE }).toGenericString());
        //     System.out.println(ArrayList.class.getMethod("get", new Class[] { Integer.TYPE }).toGenericString());
        //     //System.out.println(ArrayList.class.getMethod("indexOf").toGenericString());
        //     return;
        // }

//        Map
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


        // String command = "classInfo:java.util.List";
        if (!command.startsWith("methods:") && 
            !command.startsWith("class:")   &&
            !command.startsWith("module:")  &&
            !command.startsWith("field:")   &&
            !command.startsWith("classInfo:") )
        {
            System.err.println("Unknown command: '" + command + "'");
            System.err.println(info);
            System.exit(1);
        }

        String prefix = command.substring(0, command.indexOf(':')).trim();
        String suffix = command.substring(command.indexOf(':') + 1).trim();

        if ("class".equals(prefix) || "classInfo".equals(prefix)) {
            String extension = ".class";
            if (suffix.endsWith(extension)) {
                suffix = suffix.substring(0, suffix.length() - extension.length());
            }

            if ("class".equals(prefix)) {
                for (Class clazz : classByShortName(suffix)) {
                    System.out.println("[JAVA/rt.jar => " + clazz.getName() + "]");
                }
            } else {
                int i = suffix.indexOf('.');
                if (i < 0) {
                    suffix = "java.lang." + suffix;
                }

                System.out.println("{{{=(");
                System.out.println(
                    MAPPER.writerWithDefaultPrettyPrinter().writeValueAsString(classInfo(Class.forName(suffix)))
                );
                System.out.println(")=}}}");
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
