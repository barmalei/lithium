package test;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class JUnit5Test {
  @Test
  void test() {
    assertEquals("22", "33", "Failed test");
  }
}
