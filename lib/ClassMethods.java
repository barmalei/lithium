package lithium;

import java.lang.reflect.*;
import java.util.List;
import java.util.ArrayList;

public class ShowClassMethods {
    public static void printMethods(Class clazz) throws Exception {
        Method[]  methods   = clazz.getMethods();
        for (Method method :  methods) {
            System.out.print(clazz.getName() + "." + method.getName() + "(");
            int c = 0;
            for (Class type : method.getParameterTypes()) {
                if (c > 0) {
                    System.out.print(",");
                }
                System.out.print(type.getName());
                c++;
            }
            System.out.println(")");
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0 || args[0].trim().length() == 0) {
            System.err.println("No class name has bee passed as an argument");
            System.exit(1);
        }


        int count = 0;
        for (Class clazz : classByShortName(args[0])) {
            count++;
            System.out.println("[JAVA/rt.jar => " + clazz.getName() + "]");
        }
    }
}
