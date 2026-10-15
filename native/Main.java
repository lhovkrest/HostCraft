package dev.hostcraft.bootstrap;

import java.lang.reflect.InvocationTargetException;
import java.util.Arrays;
import java.util.jar.JarFile;

public final class Main {
    public static void main(String[] args) throws Throwable {
        if (args.length == 1 && args[0].equals("--self-test")) {
            System.out.println("HostCraft Java ready: " + System.getProperty("java.version"));
            System.out.println("Architecture: " + System.getProperty("os.arch"));
            // Exercise DNS, TLS trust initialization, native zip and networking.
            javax.net.ssl.SSLContext.getDefault();
            try (var socket = new java.net.ServerSocket(0)) {
                System.out.println("TCP bind successful: " + socket.getLocalPort());
            }
            return;
        }
        if (args.length == 0) throw new IllegalArgumentException("Server JAR required");
        String main;
        try (var jar = new JarFile(args[0])) {
            main = jar.getManifest().getMainAttributes().getValue("Main-Class");
        }
        if (main == null) throw new IllegalArgumentException("Server JAR has no Main-Class");
        try {
            Class.forName(main).getMethod("main", String[].class)
                .invoke(null, (Object) Arrays.copyOfRange(args, 1, args.length));
        } catch (InvocationTargetException ex) { throw ex.getCause(); }
    }
}
