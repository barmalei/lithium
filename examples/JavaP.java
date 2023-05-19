package test;

import com.github.javaparser.StaticJavaParser;

public class JavaP {
    public static void main(String[] args) throws Exception {

        System.out.println(
            StaticJavaParser.parse(new java.io.FileInputStream("Navigator.java"))
        );

    }
}