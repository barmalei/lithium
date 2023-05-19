package test;

import java.util.Map;
import java.util.HashMap;

/**
 *   Query class.
 */
public class test {
    private Map data;

    public test() {
        this.data  = new HashMap();
        this.data.put("a", 10);
        this.data.put("b", 11);
        this.data.put("c", 12);
    }

    public Map get() {
        return data;
    }

    public static void main(String[] args) {
        System.out.println(new test().get());
    }
}