package test;

import java.lang.reflect.*;

public class ClassMethods {
    public static void main(String[] args) throws Exception {
        String    className = "java.util.Map";
        Class     clazz     = Class.forName(className);
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
}