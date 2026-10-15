import java.util.Scanner;
public class FakeServer {
  public static void main(String[] args) {
    System.out.println("Done (0.1s)! Fake server ready");
    try (Scanner input = new Scanner(System.in)) {
      while (input.hasNextLine()) {
        String line = input.nextLine();
        if (line.equals("crash")) { System.err.println("Simulated failure"); System.exit(7); }
        if (line.equals("stop")) { System.out.println("World saved. Goodbye."); return; }
        System.out.println("Received: " + line);
      }
    }
  }
}
